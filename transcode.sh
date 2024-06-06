#!/bin/bash

# Default values
input_dir=""
export output_dir=""
parallel_processes=3
export bitrate="12M"  # Default bitrate
follow_symlinks=false
include_subdirs=false
export two_pass=false


# Function to display script usage
function usage {
    echo "Usage: $0 -i <input_directory> -o <output_directory> -b <bitrate>"
    echo "Options:"
    echo "  -i, --input <input_directory>      Input directory containing files to transcode"
    echo "  -o, --output <output_directory>    Output directory to save transcoded files"
    echo "  -d  --directory <directory>        Input AND Output directory for files for transcoding and transcoded files"
    echo "  -b, --bitrate <bitrate>            Bitrate for AV1 encoding (e.g., 6M for 6 Mbps)"
    echo "  -p, --parallel <num_processes>     Number of parallel processes (default: 5)"
    echo "  -L, --follow-symlinks              Follow symlinks"
    echo "  -S, --include-subdirs              Include subdirectories"
    echo "  -2, --two-pass                     Enable two-pass encoding"
    exit 1
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -i|--input)
            input_dir="$2"
            shift 2
            ;;
        -o|--output)
            export output_dir="$2"
            shift 2
            ;;
        -d|--directory)
            input_dir="$2"
            export output_dir="$2"
            shift 2
            ;;
        -b|--bitrate)
            export bitrate="$2"
            shift 2
            ;;
        -p|--parallel)
            parallel_processes="$2"
            shift 2
            ;;
        -L|--follow-symlinks)
            follow_symlinks=true
            shift 1
            ;;
        -S|--include-subdirs)
            include_subdirs=true
            shift 1
            ;;
        -2|--two-pass)
            two_pass=true
            shift 1
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option: $1"
            usage
            ;;
    esac
done

# Check if input and output directories are provided
if [[ -z "$input_dir" || -z "$output_dir" ]]; then
    echo "Error: Input and output directories are required."
    usage
fi

# Check if output directory exists, if not, ask to create it
if [[ ! -d "$output_dir" ]]; then
    read -p "Output directory does not exist. Do you want to create it? (y/n): " answer
    case $answer in
        [Yy]* )
            mkdir -p "$output_dir"
            echo "Output directory created."
            ;;
        * )
            echo "Exiting script. Please create or change the output directory and rerun the script."
            exit 1
            ;;
    esac
fi

# Function to perform 2-pass transcoding
function transcode_file {
    input_file="$1"
    #output_file="${input_file%.*}-AV1.${input_file##*.}"
    output_filename=$(basename "${input_file%.*}") # Get only file name from input file
    output_file_extension="${input_file##*.}" # Get file extension from input file
    output_file="$output_dir/$output_filename-AV1.$output_file_extension"
    log_file="${output_file%.*}.log"

    if [[ -f "$output_file" || "$input_file" == *"-AV1.mkv" ]]; then
        echo "Skipping $input_file as it has already been transcoded"
        return
    fi

    if [ "$two_pass" = true ]; then
        konsole -e bash -c "\
            rm \"${log_file}\"-0.log
            ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
                -i \"$input_file\" \
                -filter:v:0 'bwdif,format=nv12,hwupload' \
                -c:v av1_vaapi -b:v \"$bitrate\" -an -sn \
                -pass 1 -passlogfile \"$log_file\" -f null /dev/null
            konsoleprofile ColorScheme=Solarized
            ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
                -i \"$input_file\" \
                -filter:v:0 'bwdif,format=nv12,hwupload' \
                -map 0:v:0 -map 0:a? -map 0:s? -map 0:t? \
                -c:a copy -c:s copy -c:v:0 av1_vaapi -b:v \"$bitrate\" \
                -pass 2 -passlogfile \"$log_file\" \"$output_file\";
            rm \"${log_file}\"-0.log
            echo ""
            echo ""
            echo "DONE"
            sleep 10"
    #        read -p 'Press Enter to exit.'
    else
        konsole -e bash -c "\
            rm \"${log_file}\"-0.log
            konsoleprofile ColorScheme=Solarized
            ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
                -i \"$input_file\" \
                -filter:v:0 'bwdif,format=nv12,hwupload' \
                -map 0:v:0 -map 0:a? -map 0:s? -map 0:t? \
                -c:a copy -c:s copy -c:v:0 av1_vaapi -b:v \"$bitrate\" \
                \"$output_file\";
            rm \"${log_file}\"-0.log
            echo ""
            echo ""
            echo "DONE"
            sleep 10"
    #        read -p 'Press Enter to exit.'
    fi
}

# Process files in parallel
export -f transcode_file

#check relevant parameters and dynamically construct fine command base on those
find_command="find"
# check for symlink option
if [ "$follow_symlinks" = true ]; then
    find_command="$find_command -L"
fi
#check for subdir optoon
if [ "$include_subdirs" = false ]; then
    find_command="$find_command \"$input_dir\" -maxdepth 1"
else
    find_command="$find_command \"$input_dir\""
fi
#construct final command
find_command="$find_command -type f -name \"*.mkv\""

#run constructed find command
eval "$find_command" | LC_ALL=C.UTF-8 parallel -j "$parallel_processes" transcode_file


echo ""
echo ""
echo ""
echo "Transcoding complete."
