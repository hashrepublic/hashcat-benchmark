#!/bin/bash

# Duration of a single mode benchmark 
duration=120

# Used to store results
modeSpeeds='{}'

function set_mode_speed() {
    local key="$1"
    local value="$2"
    modeSpeeds=$(echo "$modeSpeeds" | jq --arg k "$key" --arg v $value '. + {($k): $v}')
}

function get_mode_speed() {
    local key="$1"
    echo "$modeSpeeds" | jq -r ".\"$key\" // \"Key not found\""
}

function convert_speed() {
    local input="$1"
    local value unit

    input=$(echo "$input" | tr '[:lower:]' '[:upper:]' | sed 's/[[:space:]]*$//')

    value=$(echo "$input" | sed -r 's/^([0-9.]+).(.*)$/\1/')
    unit=$(echo "$input"  | sed -r 's/^([0-9.]+).(.*)$/\2/')

    case "$unit" in
        "H/S")   multiplier=1 ;;
        "KH/S")  multiplier=1000 ;;
        "MH/S")  multiplier=1000000 ;;
        "GH/S")  multiplier=1000000000 ;;
        "TH/S")  multiplier=1000000000000 ;;
    esac

    result=$(echo "scale=0; $value * $multiplier" | bc)
    result=$(printf "%.0f" "$result")   
    echo "$result"
}

function genMask() {
    length=$1
    string=$(od -vAn -N"$length" -tx1 < /dev/urandom | tr -d ' \n' | head -c "$length")
    count=0
    num_replacements=$(( length < 7 ? $length : 7 ))
    for (( i=0; i<num_replacements ; i++ )); do
        # Place at the end
        pos=$((${#string} - $i - 1))
        # Place at the beggining
        # pos=$(($i))
        string="${string:0:pos}_${string:pos+1}"
    done
    string="${string//_/?b}"
    echo "$string"
}

function getMaxPasswordLength() {
    mode=$1
    session="hashcat-bench-$mode"
    hash="samples/$mode"
    hashcatCmd="hashcat $optimized -m $mode -a 3 $hash '$mask' | tee -a $session.txt"
    pkill hashcat
    echo "" > "$session.txt"
    screen -S $session -X quit 1> /dev/null 2> /dev/null
    screen -dmS $session bash -c "$hashcatCmd" 1> /dev/null 2> /dev/null
    sleep 5
    screen -S $session -p 0 -X stuff 'q' 1> /dev/null 2> /dev/null
    screen -S $session -X quit 1> /dev/null 2> /dev/null
    cat $session.txt | grep "Maximum password length supported by kernel" | cut -d ":" -f 2
}

function waitBenchStarted() {
    fname=$1
    while ! grep -q "\[s\]tatus \[p\]ause \[b\]ypass \[c\]heckpoint \[f\]inish \[q\]uit" "$fname"; do
        sleep 1  # Wait 1 second before checking again
    done
}

function benchmark() {
    mode=$1
    session="hashcat-bench-$mode"
    hash="samples/$mode"
    maskLen=$(getMaxPasswordLength $mode)
    mask=$(genMask $maskLen)
    hashcatCmd="hashcat $optimized -m $mode -a 3 $hash '$mask' | tee -a $session.txt"

    echo "Benchmarking mode: $mode (maskLen:$maskLen)" 
    pkill hashcat
    echo "" > "$session.txt"
    screen -S $session -X quit 1> /dev/null 2> /dev/null
    screen -dmS $session bash -c "$hashcatCmd" 1> /dev/null 2> /dev/null
    waitBenchStarted "$session.txt"
    sleep $duration
    screen -S $session -p 0 -X stuff 's' 1> /dev/null 2> /dev/null
    sleep 5
    rawSpeed=$(cat "$session.txt" | grep Speed  | awk '{lines[NR] = $0} END {for (i = NR; i > 0; i--) print lines[i]}'  | cut -d ':' -f 2- | xargs | cut -d '(' -f 1)
    speed=$(convert_speed "$rawSpeed")
    screen -S $session -p 0 -X stuff 'q' 1> /dev/null 2> /dev/null
    screen -S $session -X quit 1> /dev/null 2> /dev/null
    if grep -q "larger than the maximum password length" "$session.txt"; then
        echo "quitting due to issue with mask length, ask a dev to fix it ..."
        exit 1
    fi
    
   set_mode_speed "$mode" "$speed"
   rm $session.txt
   echo "           result: $rawSpeed"
   echo ""
   echo "$modeSpeeds" > benchmark-result.json
}

userMode=$(echo "$*" |  tr '[:lower:]' '[:upper:]' | sed 's/-O//' | sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//')
optimized=""
if [[ " $* " == *" -O "* ]]; then
    echo "Benchmarking in optimized mode '-O'" 
    optimized="-O"
else 
    echo "Benchmarking in regular mode no '-O'" 
fi

startDate=$(date)
if [[ "$userMode" =~ ^[0-9]+$ ]]; then
    benchmark $userMode

elif [[ "$userMode" == "ALL" ]]; then
    for file in "samples"/*; do
        if [[ -f "$file" ]]; then
            mode=$(basename "$file")
            benchmark $mode
        fi
    done

else
    echo "Specify a mode number or 'ALL' for all."
fi

echo "Done benchmarking"
echo "Started: $startDate"
echo "Stopped: $(date)"