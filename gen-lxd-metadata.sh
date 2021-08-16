#!/bin/sh -efu

PROG="${PROG:-${0##*/}}"

show_usage()
{
	[ -z "$*" ] || echo "$*"
	echo "Try \`$PROG --help' for more information." >&2
	exit 1
}

show_help()
{
	cat <<EOF
$PROG - generate lxd metadata in tar.xz format

Usage: $PROG [options] <output filename>

Options:
  --architecture=ARCH                 set architecture;
  --date=DATE | --creation-date=DATE  set creation date
  --description=DESCRIPTION           set description;
  --expiry-date=DATE                  set expiration date;
  --name=NAME                         set name;
  --os=OS                             set os;
  --release=REALEASE                  set realease;
  --serial=SERIAL                     set serial;
  --variant=VARIANT                   set image variant;
  --template-hosts                    add hosts template;
  -V | --version                      print version;
  -h, --help                          show this text and exit.
EOF
	exit
}

TEMP="$(getopt -n $PROG -o V,h -l version,help,architecture:,date:,creation_date:,description:,expiry_date:,name:,os:,release:,serial:,variant:,template-hosts -- "$@")" ||
	show_usage

architecture=
creation_date=
expiry_date=
description=
name=
os=alt
release=sisyphus
serial=
variant=default
template_hosts=

eval set -- "$TEMP"

while :; do
	case "$1" in
		--architecture) architecture="$2"; shift ;;
		--date|--creation-date) creation_date="$2"; shift ;;
		--description) description="$2"; shift ;;
		--expiry-date) expiry_date="$2"; shift ;;
		--name) name="$2"; shift ;;
		--os) os="$2"; shift ;;
		--release) release="$2"; shift ;;
		--serial) serial="$2"; shift ;;
		--variant) variant="2"; shift ;;
		--template-hosts) template_hosts=1 ;;
		-V|--version) print_version ;;
		-h|--help) show_help ;;
		--) shift; break ;;
	esac
	shift
done

if [ -z "$architecture" ] || [ -z "$description" ] || [ -z "$name" ]; then
	show_usage '--architecture, --description, and --name are required'
fi

[ "$#" -ge 1 ] || show_usage 'Insufficient arguments.'
[ "$#" -le 1 ] || show_usage 'Too many arguments.'
outname="$1"

if [ -n "$creation_date" ]; then
	creation_date="$(date -d "$creation_date" +%s)"
else
	creation_date="$(date +%s)"
fi

if [ -n "$expiry_date" ]; then
	expiry_date="$(date -d "$expiry_date" +%s)"
else
	expiry_date="$(($creation_date + 2592000))"
fi

date="$(date -d "@$creation_date" +%Y%m%d_%H%M)"

[ -n "$serial" ] ||
	serial="$date"

mapped_architecture="$architecture"
case "$architecture" in
	x86_64) mapped_architecture=amd64 ;;
esac

tmpdir=
cleanup_tmpdir()
{
	[ -z "$tmpdir" ] || rm -rf -- "$tmpdir"
	exit "$@"
}

tmpdir=$(mktemp -dt "${0##*/}.XXXXXXXX")
trap 'cleanup_tmpdir $?' EXIT
trap 'exit 143' HUP INT QUIT PIPE TERM

write_metadata() {
	local d="$1"; shift
	cat >"$d"/metadata.yaml <<@@@
architecture: $mapped_architecture
creation_date: $creation_date
expiry_date: $expiry_date
properties:
  architecture: $architecture
  description: $description ($date)
  name: $name-$date
  os: $os
  release: $release
  serial: "$serial"
  variant: $variant
@@@
}

write_hosts_template() {
	local d="$1"; shift
	local templates="$d"/templates
	mkdir -p "$templates"

	# This is ok as long as we support only one template.
	cat >>"$d"/metadata.yaml <<@@@
templates:
  /etc/hosts:
    when:
    - create
    - copy
    create_only: false
    template: hosts.tpl
    properties: {}
@@@

	cat > "$templates"/hosts.tpl <<@@@
127.0.1.1	{{ container.name }}
127.0.0.1	localhost.localdomain localhost
@@@
}

write_metadata "$tmpdir"
[ -z "$template_hosts" ] ||
	write_hosts_template "$tmpdir"

tar -c --auto-compress -f "$outname" -C "$tmpdir" metadata.yaml templates
