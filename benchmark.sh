#!/bin/bash

# Duration of a single mode benchmark 
duration=120

# Delay between benchmarks (when you don't want to burn your GPU)
delayBetween=10

# Start At Mode
startMode=0

# Charset (Everything except: H,h,A,a,S,s,C,c,T,t, to avoid cracking sample hashes)
charset='000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F404244454647494A4B4C4D4E4F50515255565758595A5B5C5D5E5F606264656667696A6B6C6D6E6F70717275767778797A7B7C7D7E7F808182838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9FA0A1A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBFC0C1C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDEDFE0E1E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFEFF'

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

function generate_hex_pair() {
  printf "%02X" $((RANDOM % 256))
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

    output_string=""
    for (( i=0; i<${#string}; i++ )); do
        char="${string:$i:1}"
        if [[ "$char" == "_" ]]; then
            output_string+="?1"
        else
            output_string+="$(generate_hex_pair)"
        fi
    done

    echo "$output_string"
}

function getMaxPasswordLength() {
    mode=$1
    session="hashcat-bench-$mode"
    hash="samples/$mode"
    hashcatCmd="hashcat $optimized --hex-charset -1 $charset --potfile-path=$session.pot -m $mode -a 3 $hash '$mask' | tee -a $session.txt"
    pkill hashcat
    echo "" > "$session.pot" 
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
    hashcatCmd="hashcat $optimized --hex-charset -1 $charset --potfile-path=$session.pot -m $mode -a 3 $hash '$mask' | tee -a $session.txt"
    # echo $hashcatCmd
    echo "Benchmarking mode: $mode (maskLen:$maskLen)" 
    pkill hashcat
    echo "" > "$session.pot"
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
   rm "$session.pot" 
   rm "$session.txt"
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
    for file in $(ls "samples"/* | sort -V); do
        if [[ -f "$file" ]]; then
            mode=$(basename "$file")
            if [ "$mode" -lt "$startMode" ]; then
                continue
            fi

            benchmark $mode
            sleep $delayBetween
        fi
    done

else
    echo "Specify a mode number or 'ALL' for all."
fi

echo "Done benchmarking"
echo "Started: $startDate"
echo "Stopped: $(date)"