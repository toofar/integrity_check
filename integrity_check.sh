#!/bin/sh

usage () {
  echo "Usage: $0 [-hra] [-t secs] path"

  echo "Look at the xattrs shatag.{ts,sha256} of all files under \$path"
  echo "and print a message if mtime==shatag.ts and sha256!=shatag.sha256."
  echo "Recomputes xattrs if absent of mtime has changed"
  echo "Only process files with an unchanged mtime for \$sec seconds."

  echo "-h, --help            this help"
  echo "-r, --random          (default) shuffle the list of files to check"
  echo "-a, --all             don't shuffle the list, check if the sha"
  echo "                      has changed for all the files with unchanged"
  echo "                      mtimes in order as find outputs them"
  echo "-t, --time-limit sec  stop processing after sec seconds"
  #echo "-n, --num-limit num   stop processing after num files"
}

shuf="shuf" # default, so we can be stopped after a certain amount of time but
            # still get some coverage over a few runs.

while [ -n "$1" ] ;do
  case "$1" in
    -n|--num-limit)
      shift
      echo $((${1}+0)) >/dev/null 2>&1 || {
        echo "Invalid argument: -n takes the number of files to process." >&2
        usage
        exit 1
      }
      endnum=$1
      ;;
    -t|--time-limit)
      shift
      echo $((${1}+0)) >/dev/null 2>&1 || {
        echo "Invalid argument: -t takes the run time limit in seconds." >&2
        usage
        exit 1
      }
      endtime=$1
      ;;
    -r|--random) true ;;
    -a|--all)
      shuf="cat"
      ;;
    --)
      shift
      break
      ;;
    *)
      [ -e "$1" ] && break
      echo "Unrecognised argument: $1" >&2
      usage
      exit 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
  esac
  shift
done

[ -z "$1" ] && usage && exit 0

type attr >/dev/null 2>&1 || {
  echo "Error: the attr program is required to read filesystem extended attributes." >&2
  exit 1
}

tag() {
  [ -z "$1" ] && return 1
  [ -e "$1" ] || return 2
  [ -w "$1" ] || {
    echo "Error: not writable: $1" >&2
    return 3
  }

  sha="$(sha256sum "$1")"
  attr -s shatag.sha256 -V "${sha%% *}" "$1" >/dev/null
  attr -s shatag.ts -V "$(stat -c %Y "$1")" "$1" >/dev/null
}

toprocess="$(
find "$@" -type f | while read f;do
  stime="$(attr -qg shatag.ts "$f" 2>/dev/null)" || {
    tag "$f"
    continue
  }
  stime="${stime%.*}" # chomp milliseconds
  mtime="$(stat -c %Y "$f")"

  [ $mtime -eq $stime ] || {
    # File has been modified, update xattrs
    # We could also print out if mtime < stime.
    tag "%f"
    continue
  }

  echo "$f"
done
)"
endtime=$(($(date +%s)+$endtime))

echo "$toprocess" | $shuf | while read f;do
  [ -n "$endtime" ] && [ $(date +%s) -ge $endtime ] && exit 0
  # We are in a subshell, need to check scope of endnum if we increment it
  #[ -n "$endnum" ] && [ $processed -ge $endnum] && exit 0

  oldsha="$(attr -qg shatag.sha256 "$f" 2>/dev/null)" || {
    # we may want to pull files withought a tag into toprocess too, could just
    # prefix with TOTAG: or something and add a case block where toprocess is
    # consumed.
    tag "$f"
    continue
  }

  newsha="$(sha256sum -b "$f")"
  newsha="${newsha%% *}" # chomp filename

  [ $newsha = $oldsha ] && continue

  # If the file changes between the time it is added to toprocess and
  # now we claim it is corrupted, re-check that mtime=stime.
  stime="$(attr -qg shatag.ts "$f" 2>/dev/null)" || {
    tag "$f"
    continue
  }
  stime="${stime%.*}" # chomp milliseconds
  mtime="$(stat -c %Y "$f")"

  [ $mtime -eq $stime ] || {
    # File has been modified, update xattrs
    # We could also print out if mtime < stime.
    tag "%f"
    continue
  }

  # Sha has changed but mtime hasn't; fs corruption?
  echo "$oldsha -> $newsha: $f"
done

