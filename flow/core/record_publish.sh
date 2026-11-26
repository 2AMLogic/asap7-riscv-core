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
# after preflight. The private directory belongs to this helper alone: it
# removes it on success and on every failure and never lists it in CREATED,
# so a rollback cannot unlink a name another publisher has since reused.
#
# The copy is written by a plain redirect inside that private directory,
# which mktemp -d creates 0700 and which inherits the record directory's
# default ACL; the file is therefore created with the permissions the
# filesystem would give a plain redirect in the record directory (umask or
# default ACL), and no chmod is applied. The hard link shares that inode.
#
# Needs GNU coreutils: mktemp -d's template form and ln -T, which treats a
# directory at the final pathname as the collision it is instead of adding
# the link inside it (the flow's Linux host, like the --export rename).
#
# Provides:
#   record_publish <stage-dir> <record-dir> <name>...
#                                        install <stage-dir>/<name> as <record-dir>/<name>, in order;
#                                        non-zero at the first name that cannot be installed
#   record_install <staged-file> <dest>  install one file exclusively: non-zero when the copy or
#                                        the link fails; <dest> joins CREATED once the link
#                                        succeeded; the private directory never does

record_publish() {  # stage-dir record-dir name... -- install each, in order
  local stage="$1" dir="$2" name
  shift 2
  for name in "$@"; do
    record_install "$stage/$name" "$dir/$name" || return 1
  done
}

record_install() {  # staged-file dest-pathname -- install exclusively, owning dest once linked
  local src="$1" dest="$2" dir base tmpd tmp
  dir="$(dirname -- "$dest")"
  base="$(basename -- "$dest")"
  tmpd="$(mktemp -d -- "$dir/.$base.XXXXXX")" || return 1
  tmp="$tmpd/$base"
  if ! cat -- "$src" >"$tmp"; then rm -rf -- "$tmpd"; return 1; fi
  if ! ln -T -- "$tmp" "$dest"; then rm -rf -- "$tmpd"; return 1; fi
  CREATED+=("$dest")
  rm -rf -- "$tmpd" || return 1
}
