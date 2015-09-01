#!/bin/bash
##
## Git.sh (Shit): Git implementation written in bash
## Copyright (C) 2015 SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 3
##

set -u
set -o pipefail
shopt -s lastpipe

Shit_GitDir=".git"
## FIXME: ?
Shit_IntSize=4

typeset -A Shit_Struct

Shit_Struct[index_header]="
  dirc:string:4
  version:int
  entries:int
"

Shit_Struct[index_entry]="
  ctime_sec:int
  ctime_nsec:int
  mtime_sec:int
  mtime_nsec:int
  dev:int
  ino:int
  mode:int
  uid:int
  gid:int
  size:int
  sha1:hexstring:20
  zero:byte
  name_length:byte
"

## ======================================================================

Shit_Die()
{
  echo -E "ERROR: $*" 1>&2
  exit ${2-1}
}

Shit_Debug()
{
  [[ -n ${SHIT_DEBUG+set} ]] || return
  echo -E "DEBUG: $*" 1>&2
}

Shit_HexStdin()
{
  od -tx1 \
  |sed \
    -e 's/^[^ ]* *//' \
    -e '/^$/d' \
    -e 's/  */ /g' \
  |tr ' ' '\n' \
  ;
}

Shit_ReadIntegerFromHexLines()
{
  local size="${1-Shit_IntSize}"; shift
  local n=0
  local i
  local b

  ## FIXME: Endian?
  for ((; size > 0; size--)); do
    read -r b || return 1
    let "n = (n << 8) + 0x$b"
  done

  echo -E "$n"
  return 0
}

Shit_ReadStringFromHexLines()
{
  local size="$1"; shift
  local b
  local s=
  local eos=

  for ((; size > 0; size--)); do
    read -r b || return 1
    [[ $b == "00" ]] && eos=set
    [[ -n $eos ]] && continue
    s="$s$(echo -ne '\x'"$b")"
  done

  echo -E "$s"
}

Shit_ReadHexStringFromHexLines()
{
  local size="$1"; shift
  local b
  local s=
  local eos=

  for ((; size > 0; size--)); do
    read -r b || return 1
    s="$s$b"
  done

  echo -E "$s"
}

Shit_ReadStructFromHexLines()
{
  local s_type="$1"; shift
  local s_name="${1-$s_type}"; ${1+shift}
  local m_name
  local m_type
  local m_size
  local m_value

  for m_desc in ${Shit_Struct[$s_type]}; do
    m_name="${m_desc%%:*}"
    m_type="${m_desc#*:}"

    case "$m_type" in
    int)
      m_value=$(Shit_ReadIntegerFromHexLines)
      ;;
    byte)
      m_value=$(Shit_ReadIntegerFromHexLines 1)
      ;;
    string:*)
      m_value=$(Shit_ReadStringFromHexLines "${m_type#*:}")
      ;;
    hexstring:*)
      m_value=$(Shit_ReadHexStringFromHexLines "${m_type#*:}")
      ;;
    *)
      Shit_Die "Invalid member definition in struct: $s_name: $m_desc"
      ;;
    esac

    eval "$s_name"'[$m_name]="$m_value"'
    Shit_Debug "$s_name[$m_name]=\"$m_value\""
  done
}

## ======================================================================

Shit_init()
{
  mkdir .git || exit 1
  mkdir .git/objects || exit 1
  mkdir .git/refs || exit 1
  echo -E 'ref: refs/heads/master' >.git/HEAD || exit 1
}

Shit_ls_files()
{
  local opt
  local stage_p=

  while [[ $# -gt 0 ]]; do
    opt="$1"; shift

    if [[ -z "${opt##-[!-]?*}" ]]; then
      set -- "-${opt#??}" ${1+"$@"}
      opt="${opt%${1#-}}"
    fi
    if [[ -z "${opt##--*=*}" ]]; then
      set -- "${opt#--*=}" ${1+"$@"}
      opt="${opt%%=*}"
    fi

    case "$opt" in
    -s|--stage)
      stage_p="set"
      ;;
    --)
      break
      ;;
    -*)
      Shit_Die "Invalid option: $opt"
      ;;
    *)
      set -- "$opt" ${1+"$@"}
      break
      ;;
    esac
  done

  local dirc
  local version
  local entries
  local i

  Shit_HexStdin <"$Shit_GitDir/index" \
  |{
    typeset -A index_header index_entry
    Shit_ReadStructFromHexLines index_header
    Shit_Debug "${index_header[dirc]}"

    for ((i=0; i < ${index_header[entries]}; i++)); do
      Shit_ReadStructFromHexLines index_entry
      index_entry[name]=$(Shit_ReadStringFromHexLines "${index_entry[name_length]}")

      local padding=$((
	(((${index_entry[name_length]} - 2) / 8 + 1) * 8 + 2) -
	${index_entry[name_length]}
      ))
      Shit_ReadIntegerFromHexLines "$padding" >/dev/null

      if [[ -n $stage_p ]]; then
	printf '%o %s 0\t%s\n' \
	  "${index_entry[mode]}" \
	  "${index_entry[sha1]}" \
	  "${index_entry[name]}" \
	;
      else
	echo -E "${index_entry[name]}"
      fi
    done
  }
}

if [[ ${#BASH_SOURCE[@]} -eq 1 ]]; then
  cmd_name="${1//-/_}"; shift
  if ! type "Shit_$cmd_name" >/dev/null 2>&1; then
    Shit_Die "Invalid command: $cmd_name"
  fi
  "Shit_$cmd_name" "$@"
fi

