#! /bin/bash

# Globals and defaults

SCRIPT_PID="$$"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PANIC_MESSAGE_FILE=$(mktemp)
trap "cat $PANIC_MESSAGE_FILE; exit 127" SIGUSR1

# Defaults and constants
MAX_GRID_SIZE=30
VIEWPORT_TEMPLATE_FILE="$SCRIPT_DIR/live-stream-viewport.html.template"
VIEWPORT_PAGE=viewport.html

DEFAULT_OUTPUT_DIR='.'
DEFAULT_LAYOUT='2x2'

#
# Utility functions
#

log() {
    [[ -z "$VERBOSE" ]] && return
    local _message="$1"
    local _now=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$_now] $_message" >/dev/stderr
}

panic() {
    local _message="$1"
    log "$_message"
    echo "$_message" >"$PANIC_MESSAGE_FILE"
    kill -SIGUSR1 "$SCRIPT_PID"
    exit
}

process_running() {
  local _name="$1"
  local _pid="$2"

  (( _pid == 0 )) && return 127

  case "$(uname)" in
    Darwin)
      pgrep "$_name" | grep "$_pid" &>/dev/null
      return "$?"
      ;;

    Linux)
      [[ "$(ps | grep "$_pid" | head -1 | awk '{print $4}')" == "$_name" ]]
      return "$?"
  esac
}

#
# Usage and help functions
#

usage() {
    echo "usage: $(basename $0) [-vh] [-o <output-dir>] [-l <layout>] -s <id=rtsp-url>..."
}

help() {
    cat <<EOF
NAME:
    $(basename $0) - View rtsp/rtsps streams in a web browser.

SYNOPSIS:
    This program offers a simple  method to display multiple, side-by-side real
    time streaming protocol (RTSP)  streams in a  web browser, making  it ideal
    for passive, security cameras view-only scenarios (i.e., 'kiosk').

    The program starts by generating a simple web page for viewing the supplied
    streams ('viewport'),  and then by running in  the background,  for each of
    the streams,  a transcoder program (ffmpeg) that translates  the RTSP/RTSPS
    stream into a http live stream (hls) stream. These HLS streams are suitable
    for easy consumption by the previously generated web page.

    Note: A web server is needed to serve the viewport and streams.

USAGE:
    $(basename $0) [-o <output-dir>] [-l <layout>] -s <id=url>...

STANDARD OPTIONS:
    -v                Be verbose.
    -h, --help        Print this help and exit.

OPTIONS:
    -o <output-dir>   Directory where the output should go [default: .]
    -l <layout>       Viewport layout in rows x columns format [default: 2x2]
    -s <id=url>       Stream id and url in the form of 'id=rtsp[s]://address'

EXAMPLE:
    The following is used to view two streams,  side by side,  in a 1x2 layout.
    The streams  are transcoded concurrently  in the background.  The resulting
    temporary files are stored in /var/www/htdocs,  which is expected to be the
    root  directory  of the  web server.  The viewport can then be accessed  by
    navigating to: http://localhost/viewport.html.

    $(basename $0) \\
      -o /var/www/htdocs \\
      -l 1x2 \\
      -s 'door-camera=rtsp://192.168.4.101:7441/d3xxdde0xa9jn' \\
      -s 'pool-camera=rtsps://192.168.4.10:7447/f1gzgge0xt1sn?nightmode=false'

EOF
}

#
# The parse_and_validate_output_dir function is responsible for parsing and
# validating the provided output directory. If the provided directory is null,
# it defaults to a specified directory. It verifies that the directory exists
# and is writable.
#
# Positional parameters:
#   (1) <output_dir>: The desired output directory specified by the user. It
#   can be an empty string, meaning that the function should use the default
#   directory.
#
#   (2) <default_output_dir>: The default output directory to be used if
#   <output_dir> is empty or null.
#
# Returns:
#   The validated output directory path.
#
parse_and_validate_output_dir() {
  local _output_dir="$1"
  local _default_output_dir="$2"

  log "Parsing and validating output-dir, input is '$_output_dir'"
  if [[ -z "$_output_dir" ]]; then
    _output_dir="$_default_output_dir"
    log "Using default output dir '$_output_dir'"
  fi

  [[ ! -d "$_output_dir" ]] && panic "Error. Directory '$_output_dir' doesn't exist."
  if ! touch "$_output_dir"/touch 2>/dev/null; then
    panic "Error. Directory '$_output_dir' is not writable."
  fi
  rm "$_output_dir"/touch

  echo "$_output_dir"
}

#
# The parse_and_validate_layout function is responsible for parsing and
# validating a layout string, which specifies a grid in the form of rows and
# columns. If the input layout is null, it defaults to a specified layout. It
# verifies that the grid size is within acceptable bounds.
#
# Positional parameters:
#   (1) <layout>: The desired layout specified by the user in the format NxM,
#       where N is the number of rows and M is the number of columns. It can
#       be an empty string, meaning that the function should use the default
#       layout.

#   (2) <default_layout>: The default layout to be used if <layout> is empty
#       or null.
#
# Returns:
#   The number of rows and columns as separate echoed values.
#
parse_and_validate_layout() {
  local _layout="$1"
  local _default_layout="$2"

  log "Parsing and validating layout, input is '$_layout'"

  if [[ -z "$_layout" ]]; then
    _layout="$_default_layout"
    log "Using default layout '$_layout'"
  fi

  local _rows=${_layout%x*}
  local _columns=${_layout#*x}
  log "Layout rows=$_rows, layout columns=$_columns"

  local _grid_size=$((_rows * _columns))
  if (( _grid_size < 1 )) || (( _grid_size > MAX_GRID_SIZE )); then
    panic "Error. Layout grid size of $_grid_size is out of bounds."
  fi

  echo "$_rowsx$_columns"
}

#
# The parse_and_validate_streams function is responsible for parsing and
# validating a list of streams provided in the format id=url. It checks if
# each stream has a valid id=url structure, ensures no duplicate IDs exist,
# and verifies that the URLs use supported protocols (RTSP or RTSPS).
#
# Positional parameters:
#   (1)...(N) <stream1> <stream2> ...: A list of streams, each specified in
#      a format of 'id=url'.
#
# Returns:
#   A list of validated streams in the format <id=url> <id=url>...
#
parse_and_validate_streams() {
  local _streams=("$@")

  log "Parsing and validating streams, input is '$_streams'"

  local _temp_dir=$(mktemp -d)
  for _id_url in "${_streams[@]}"; do
    log "Parsing $_id_url"

    local _id=${_id_url%=*}
    local _url=${_id_url#*=}

    [[ "$_id" =~ [=:/] ]] && panic "Stream id cannot have the '=:/' chars in it."

    [[ -f "$_temp_dir/$_id" ]] && panic "Error. The stream id '$_id' was already given."
    touch "$_temp_dir/$_id"

    local _protocol=$(echo "${_url}" | awk -F '/' '{print substr($1, 1, length($1)-1)}')
    log "Protocol is '$_protocol'"
    case "$_protocol" in
       rtsp|rtsps) ;;
       http|https) ;;
       file) ;;
       *) panic "Error. Unsupported protocol in url '$_url'" ;;
    esac
  done

  echo "${_streams[@]}"
}

#
# The generate_viewport_page function generates an HTML viewport page based on
# a template file. It populates the template with layout information and stream
# IDs.
#
# Positional parameters:
#   (1) <template_file>: Path to the HTML template file that contains place
#       holders for the layout and stream information.
#   (2) <viewport_file>: Path to the output HTML file generated from the template.
#
#   (3) <rows>: Number of rows in the layout grid.
#   (4) <columns>: Number of columns in the layout grid.

#   (5)...(N) <stream1> <stream2> ...: A list of streams, each specified in the
#       format id=url.
#
generate_viewport_page() {
  local _template_file="$1"
  local _viewport_file="$2"
  local _layout="$3"
  shift 3
  local _streams=($@)

  log "Preparing replacements for the template file $(basename "$_template_file")"

  local _rows="${_layout%x*}"
  local _columns="${_layout#*x}"
  log "Layout is $_rows x $_columns"

  local _html_rows
  for _dummy in $(seq "$_rows"); do _html_rows="$_html_rows 1fr "; done
  log "{{ROWS}} is going to be '$_html_rows'"

  local _html_columns
  for _dummy in $(seq "$_columns"); do _html_columns="$_html_columns 1fr "; done
  log "{{COLUMNS}} is going to be '$_html_columns'"


  local _html_grid_size=$(( _rows * _columns ))
  log "{{GRID_SIZE}} is going to be '$_html_grid_size'"

  local _html_stream_ids=()
  for _id_url in "${_streams[@]}"; do
    _html_stream_ids+=(\"$(echo "$_id_url" | awk -F '=' '{print $1}')\")
  done

  _html_stream_ids=$( echo "${_html_stream_ids[@]}" | tr ' ' ',' )
  log "{{STREAM_IDS}} is going to be '$_html_stream_ids'"

  log "Generating into '$_viewport_file'..."
  sed \
    -e 's/{{ROWS}}/'"$_html_rows"'/g' \
    -e 's/{{COLUMNS}}/'"$_html_columns"'/g' \
    -e 's/{{GRID_SIZE}}/'"$_html_grid_size"'/g' \
    -e 's/{{STREAM_IDS}}/'"$_html_stream_ids"'/g' \
    "$_template_file" \
    >"$_viewport_file"
}

#
# The transcode_stream function transcodes a RTSP(S) stream to HLS stream
# by running ffmpeg process in the background.
#
# Positional parameters:
#   (1) <stream_id>: The id of the stream.
#   (2) <stream_url>: The URL of the stream.
#   (3) <output_dir>: The base directory where output should go.
#
# Returns:
#   The PID of the running ffmpeg, 0 otherwise.
#

transcode_stream() {
  local _stream_id="$1"
  local _stream_url="$2"
  local _output_dir="$3"

  local _stream_output_dir="$_output_dir"/"$_stream_id"
  mkdir -p "$_stream_output_dir"

  log "Trying to start ffmpeg on url '$_stream_url'..."
  local _error_output_file="$(mktemp)"
  ffmpeg \
    -loglevel 8 \
    -i "$_stream_url" \
    -fflags flush_packets -max_delay 5 -flags -global_header \
    -hls_time 5 -hls_list_size 3 -hls_flags delete_segments \
    -vcodec copy \
    -y "$_stream_output_dir"/index.m3u8 \
    &>"$_error_output_file" \
    &

  local _pid="$!"
  sleep 1

    # Zero size?
  if [[ -s "$_error_output_file" ]]; then
    log "Error starting ffmpeg. '$(head "$_error_output_file")'"
    _pid=0
  else
    log "Successfully started ffmpeg, PID is '$_pid'"
    echo "$_pid" > "$_stream_output_dir/pid"
  fi

  echo "$_pid"
}

transcoder_running() {
  local _pid="$1"
  process_running 'ffmpeg' "$_pid"
}

#
# --- Main ---
#


#
# Handle usage and --help early, as getopt on macOS doesn't have long options.
#
if [[ $# -eq 0 ]]; then
    usage && exit 128
elif [[ "$1" == "--help" ]]; then
  help && exit 0
fi

#
# Parse command line
#
error_message_file=$(mktemp)
valid_args=$(getopt vho:l:s: "$@" 2>"$error_message_file")
if [[ $? -ne 0 ]]; then
    echo "error. $(cat "$error_message_file")" 2>/dev/stderr
    usage && exit 129
fi

eval set -- "$valid_args"
while :; do
  case "$1" in
    -v | --verbose)
      VERBOSE='true'
      log "Collecting 'verbose' option"
      shift 1
      ;;

    -h | --help)
      log "Collecting 'help' option"
      help && exit 0
      ;;

    -o | --output-dir)
      log "Collecting 'output-dir' option, input is '$2'"
      output_dir="$2"
      shift 2
      ;;

    -l | --layout)
      log "Collecting 'layout' option, input is '$2'"
      layout="$2"
      shift 2
      ;;

    -s | --stream)
      log "Collecting 'stream' option, input is '$2'"
      streams+=("$2")
      shift 2
      ;;

    --) shift;
      break
      ;;
  esac
done

#
# Parse and validate the input.
#
output_dir=$(parse_and_validate_output_dir "$output_dir" "$DEFAULT_OUTPUT_DIR");
layout=$(parse_and_validate_layout "$layout" "$DEFAULT_LAYOUT")
map_stream_id_url=( $(parse_and_validate_streams "${streams[@]}") )

#
# Generate the viewport
#
generate_viewport_page "$VIEWPORT_TEMPLATE_FILE" "$output_dir"/"$VIEWPORT_PAGE" "$layout" "${map_stream_id_url[@]}"

#
# The main Control Loop. This is used to monitor and manage transcoding
# processes for a set of streams. It keeps the streams' states updated,
# checks their statuses, and restarts them if necessary. The loop supports
# exponential backoff for the wait period between restart attempts.
#
# Main variables and data structures:
#   * map_stream_id_state: An array containing the state of each stream
#     transcoder in the format id=pid:ping_count:last_ping_epoch:wait_period.
#
#   * map_stream_id_url: An array containing the URLs of each stream in the
#     format id=url.
#
#   * output_dir: Directory where stream outputs are stored.
#
# Constants:
#   * SLEEP_PERIOD: Time to sleep (s) between control loop iterations.
#   * INITIAL_WAIT_PERIOD: Initial wait period (s) before retrying a failed stream.
#   * MAX_WAIT_PERIOD: Maximum wait period (s) before restarting a failed stream.
#   * STABLE_PERIOD: The time (s) a process has to be continuously running before
#     it is considered stable.
#

SLEEP_PERIOD=30
INITIAL_WAIT_PERIOD=10
MAX_WAIT_PERIOD=600
STABLE_PERIOD=120

# Initialize state
for id_url in "${map_stream_id_url[@]}"; do
  id=${id_url%=*}
  now_epoch=$(date +%s)

  # :pid :ping_count :last_ping_epoch :wait_period
  map_stream_id_state+=("$id=0:0:$(( now_epoch - INITIAL_WAIT_PERIOD/2)):$(( INITIAL_WAIT_PERIOD/2 ))")
done

CLEANUP_PIDS_FILE=$(mktemp)
trap "log 'Cleaning up background processes.'; <$CLEANUP_PIDS_FILE xargs -n1 kill 2>/dev/null; exit" SIGTERM SIGHUP SIGABRT

log "Starting control loop"
# And now down to business...
while :; do
  for id_state in "${map_stream_id_state[@]}"; do

    id="${id_state%%=*}"
    state="${id_state#*=}"
    pid=$(echo "$state" | awk -F ':' '{print $1}')
    ping_count=$(echo "$state" | awk -F ':' '{print $2}')
    last_ping_epoch=$(echo "$state" | awk -F ':' '{print $3}')
    wait_period=$(echo "$state" | awk -F ':' '{print $4}')

    url=$(printf '%s\n' "${map_stream_id_url[@]}" | awk -F '=' '/^'"$id"'=/{print $2}')

    now_epoch=$(date +%s)

    if transcoder_running "$pid"; then
      last_ping_epoch="$now_epoch"
      ping_count=$(( ping_count + 1 ))

      #
      # If the process is stable enough, reset the wait period back to the
      # value of INITIAL_WAIT_PERIOD. This controls situations where the
      # process starts, works for a short period and then stops, causing
      # constant restart attempts without exponential increase in wait
      # time between restarts.
      #
      if (( ping_count == STABLE_PERIOD / SLEEP_PERIOD )); then
        wait_period="$INITIAL_WAIT_PERIOD"
      fi

      #
      # Save state
      #
      state="$pid:$ping_count:$last_ping_epoch:$wait_period"
      map_stream_id_state=("${map_stream_id_state[@]/$id=*/$id=$state}")

      #
      # Get the progress this transcoder has made
      #
      section=$(awk <"$output_dir/streams/$id/index.m3u8" -F ':' '/^#EXT-X-MEDIA-SEQUENCE/{print $2}')
      log "The transcoder for stream '$id' is running, state='$state', section='$section'"
      continue

    else # Transcoder not running
      log "Transcoder for stream '$id' is not running, state='$state'"

      if (( now_epoch - last_ping_epoch >= wait_period )); then
        # Prepare for the next time
        if (( wait_period < MAX_WAIT_PERIOD )); then
          wait_period=$(( wait_period * 2 ))

          # cap at MAX_WAIT_PERIOD
          if (( wait_period >= MAX_WAIT_PERIOD )); then
            wait_period="$MAX_WAIT_PERIOD"
          fi
        fi

        log "Starting transcoder for stream '$id' on url '$url'"
        pid=$(transcode_stream "$id" "$url" "$output_dir/streams")
        if (( pid > 0 )); then
          echo "$pid" >> "$CLEANUP_PIDS_FILE"
        fi

        state="$pid:0:$now_epoch:$wait_period"
        map_stream_id_state=("${map_stream_id_state[@]/$id=*/$id=$state}")
      fi
    fi
  done

  log "Sleeping for $SLEEP_PERIOD seconds"
  sleep "$SLEEP_PERIOD"
done # forever loop

