# shellcheck shell=bash
# Exclusive publication of dated records, shared by flow/core/par.sh and
# flow/core/drc.sh. Sourced, not executed, after flow/lib.sh. The caller
# declares CREATED=() before publishing and removes those pathnames on
# rollback.
#
# ASAP7 is a predictive PDK; nothing here is fabricated or measured.
#
# A record reaches its final pathname only once its bytes are complete. The
# copy is finished under a private name in the record directory -- the same
# directory, hence one filesystem, hence one hard link -- and only then
# linked to the final pathname without replacement. The link fails when
# anything, file or directory, already holds that name, and until it succeeds
# this run owns nothing at the final pathname. A copy that therefore fails
# partway leaves no truncated record behind to read as an existing one and
# refuse the same-date retry.
#
# Ownership follows the link, never the intent: the final pathname joins
# CREATED only after this run's own link established it, so a rollback
# removes what this run published and never a file another writer created
# after preflight. The private name is this run's from the moment mktemp
# creates it, and is removed on success and on every failure.
#
# Needs GNU coreutils: mktemp's template form and ln -T, which treats a
# directory at the final pathname as the collision it is instead of adding
# the link inside it (the flow's Linux host, like the --export rename).
#
# Provides:
#   record_publish <stage-dir> <record-dir> <name>...
#                                        install <stage-dir>/<name> as <record-dir>/<name>, in order;
#                                        non-zero at the first name that cannot be installed
#   record_install <staged-file> <dest>  install one file exclusively: non-zero when the copy or
#                                        the link fails; the private copy joins CREATED when it is
#                                        created, <dest> once the link succeeded

record_publish() {  # stage-dir record-dir name... -- install each, in order
  local stage="$1" dir="$2" name
  shift 2
  for name in "$@"; do
    record_install "$stage/$name" "$dir/$name" || return 1
  done
}

record_install() {  # staged-file dest-pathname -- install exclusively, owning dest once linked
  local src="$1" dest="$2" dir base tmp
  dir="$(dirname -- "$dest")"
  base="$(basename -- "$dest")"
  tmp="$(mktemp -- "$dir/.$base.XXXXXX")" || return 1
  CREATED+=("$tmp")
  if ! cat -- "$src" >"$tmp"; then rm -f -- "$tmp"; return 1; fi
  # mktemp created the private copy 0600; a record written by a plain
  # redirect carries 0666 minus the umask, and the published file keeps that.
  chmod "$(printf '%o' "$((0666 & ~0$(umask)))")" -- "$tmp" || { rm -f -- "$tmp"; return 1; }
  if ! ln -T -- "$tmp" "$dest"; then rm -f -- "$tmp"; return 1; fi
  CREATED+=("$dest")
  rm -f -- "$tmp" || return 1
}
