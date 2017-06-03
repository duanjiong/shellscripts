#!/bin/bash
#
#
#From devstack/common_function
#

# functions-common - Common functions used by DevStack components
#
# The canonical copy of this file is maintained in the DevStack repo.
# All modifications should be made there and then sync'ed to other repos
# as required.
#
# This file is sorted alphabetically within the function groups.
#
# - Config Functions
# - Control Functions
# - Distro Functions
# - Git Functions
# - OpenStack Functions
# - Package Functions
# - Process Functions
# - Service Functions
# - System Functions
#
# The following variables are assumed to be defined by certain functions:
#
# - ``ENABLED_SERVICES``
# - ``ERROR_ON_CLONE``
# - ``FILES``
# - ``OFFLINE``
# - ``RECLONE``
# - ``REQUIREMENTS_DIR``
# - ``STACK_USER``
# - ``TRACK_DEPENDS``
# - ``http_proxy``, ``https_proxy``, ``no_proxy``
#

# Save trace setting
_XTRACE_FUNCTIONS_COMMON=$(set +o | grep xtrace)
set +o xtrace

# ensure we don't re-source this in the same environment
[[ -z "$_DEVSTACK_FUNCTIONS_COMMON" ]] || return 0
declare -r -g _DEVSTACK_FUNCTIONS_COMMON=1

# Global Config Variables
declare -A -g GITREPO
declare -A -g GITBRANCH
declare -A -g GITDIR

TRACK_DEPENDS=${TRACK_DEPENDS:-False}

# Save these variables to .stackenv
STACK_ENV_VARS="BASE_SQL_CONN DATA_DIR DEST ENABLED_SERVICES HOST_IP \
    KEYSTONE_AUTH_URI KEYSTONE_SERVICE_URI \
    LOGFILE OS_CACERT SERVICE_HOST STACK_USER TLS_IP \
    HOST_IPV6 SERVICE_IP_VERSION"


# Saves significant environment variables to .stackenv for later use
# Refers to a lot of globals, only TOP_DIR and STACK_ENV_VARS are required to
# function, the rest are simply saved and do not cause problems if they are undefined.
# save_stackenv [tag]
function save_stackenv {
    local tag=${1:-""}
    # Save some values we generated for later use
    time_stamp=$(date "+$TIMESTAMP_FORMAT")
    echo "# $time_stamp $tag" >$TOP_DIR/.stackenv
    for i in $STACK_ENV_VARS; do
        echo $i=${!i} >>$TOP_DIR/.stackenv
    done
}

# Update/create user clouds.yaml file.
# clouds.yaml will have
# - A `devstack` entry for the `demo` user for the `demo` project.
# - A `devstack-admin` entry for the `admin` user for the `admin` project.
# write_clouds_yaml
function write_clouds_yaml {
    # The location is a variable to allow for easier refactoring later to make it
    # overridable. There is currently no usecase where doing so makes sense, so
    # it's not currently configurable.

    CLOUDS_YAML=/etc/openstack/clouds.yaml

    sudo mkdir -p $(dirname $CLOUDS_YAML)
    sudo chown -R $STACK_USER /etc/openstack

    CA_CERT_ARG=''
    if [ -f "$SSL_BUNDLE_FILE" ]; then
        CA_CERT_ARG="--os-cacert $SSL_BUNDLE_FILE"
    fi
    # demo -> devstack
    $PYTHON $TOP_DIR/tools/update_clouds_yaml.py \
        --file $CLOUDS_YAML \
        --os-cloud devstack \
        --os-region-name $REGION_NAME \
        --os-identity-api-version 3 \
        $CA_CERT_ARG \
        --os-auth-url $KEYSTONE_SERVICE_URI \
        --os-username demo \
        --os-password $ADMIN_PASSWORD \
        --os-project-name demo

    # alt_demo -> devstack-alt
    $PYTHON $TOP_DIR/tools/update_clouds_yaml.py \
        --file $CLOUDS_YAML \
        --os-cloud devstack-alt \
        --os-region-name $REGION_NAME \
        --os-identity-api-version 3 \
        $CA_CERT_ARG \
        --os-auth-url $KEYSTONE_SERVICE_URI \
        --os-username alt_demo \
        --os-password $ADMIN_PASSWORD \
        --os-project-name alt_demo

    # admin -> devstack-admin
    $PYTHON $TOP_DIR/tools/update_clouds_yaml.py \
        --file $CLOUDS_YAML \
        --os-cloud devstack-admin \
        --os-region-name $REGION_NAME \
        --os-identity-api-version 3 \
        $CA_CERT_ARG \
        --os-auth-url $KEYSTONE_SERVICE_URI \
        --os-username admin \
        --os-password $ADMIN_PASSWORD \
        --os-project-name admin

    # CLean up any old clouds.yaml files we had laying around
    rm -f $(eval echo ~"$STACK_USER")/.config/openstack/clouds.yaml
}

# trueorfalse <True|False> <VAR>
#
# Normalize config-value provided in variable VAR to either "True" or
# "False".  If VAR is unset (i.e. $VAR evaluates as empty), the value
# of the second argument will be used as the default value.
#
#  Accepts as False: 0 no  No  NO  false False FALSE
#  Accepts as True:  1 yes Yes YES true  True  TRUE
#
# usage:
#  VAL=$(trueorfalse False VAL)
function trueorfalse {
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace

    local default=$1

    if [ -z $2 ]; then
        die $LINENO "variable to normalize required"
    fi
    local testval=${!2:-}

    case "$testval" in
        "1" | [yY]es | "YES" | [tT]rue | "TRUE" ) echo "True" ;;
        "0" | [nN]o | "NO" | [fF]alse | "FALSE" ) echo "False" ;;
        * )                                       echo "$default" ;;
    esac

    $xtrace
}

function isset {
    [[ -v "$1" ]]
}


# Control Functions
# =================

# Prints backtrace info
# filename:lineno:function
# backtrace level
function backtrace {
    local level=$1
    local deep
    deep=$((${#BASH_SOURCE[@]} - 1))
    echo "[Call Trace]"
    while [ $level -le $deep ]; do
        echo "${BASH_SOURCE[$deep]}:${BASH_LINENO[$deep-1]}:${FUNCNAME[$deep-1]}"
        deep=$((deep - 1))
    done
}

# Prints line number and "message" then exits
# die $LINENO "message"
function die {
    local exitcode=$?
    set +o xtrace
    local line=$1; shift
    if [ $exitcode == 0 ]; then
        exitcode=1
    fi
    backtrace 2
    err $line "$*"
    # Give buffers a second to flush
    sleep 1
    exit $exitcode
}

# Checks an environment variable is not set or has length 0 OR if the
# exit code is non-zero and prints "message" and exits
# NOTE: env-var is the variable name without a '$'
# die_if_not_set $LINENO env-var "message"
function die_if_not_set {
    local exitcode=$?
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local line=$1; shift
    local evar=$1; shift
    if ! is_set $evar || [ $exitcode != 0 ]; then
        die $line "$*"
    fi
    $xtrace
}

function deprecated {
    local text=$1
    DEPRECATED_TEXT+="\n$text"
    echo "WARNING: $text" >&2
}

# Prints line number and "message" in error format
# err $LINENO "message"
function err {
    local exitcode=$?
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local msg="[ERROR] ${BASH_SOURCE[2]}:$1 $2"
    echo $msg 1>&2;
    if [[ -n ${LOGDIR} ]]; then
        echo $msg >> "${LOGDIR}/error.log"
    fi
    $xtrace
    return $exitcode
}

# Checks an environment variable is not set or has length 0 OR if the
# exit code is non-zero and prints "message"
# NOTE: env-var is the variable name without a '$'
# err_if_not_set $LINENO env-var "message"
function err_if_not_set {
    local exitcode=$?
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local line=$1; shift
    local evar=$1; shift
    if ! is_set $evar || [ $exitcode != 0 ]; then
        err $line "$*"
    fi
    $xtrace
    return $exitcode
}

# Exit after outputting a message about the distribution not being supported.
# exit_distro_not_supported [optional-string-telling-what-is-missing]
function exit_distro_not_supported {
    if [[ -z "$DISTRO" ]]; then
        GetDistro
    fi

    if [ $# -gt 0 ]; then
        die $LINENO "Support for $DISTRO is incomplete: no support for $@"
    else
        die $LINENO "Support for $DISTRO is incomplete."
    fi
}

# Test if the named environment variable is set and not zero length
# is_set env-var
function is_set {
    local var=\$"$1"
    eval "[ -n \"$var\" ]" # For ex.: sh -c "[ -n \"$var\" ]" would be better, but several exercises depends on this
}

# Prints line number and "message" in warning format
# warn $LINENO "message"
function warn {
    local exitcode=$?
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local msg="[WARNING] ${BASH_SOURCE[2]}:$1 $2"
    echo $msg
    $xtrace
    return $exitcode
}


# Distro Functions
# ================

# Determine OS Vendor, Release and Update

#
# NOTE : For portability, you almost certainly do not want to use
# these variables directly!  The "is_*" functions defined below this
# bundle up compatible platforms under larger umbrellas that we have
# determinted are compatible enough (e.g. is_ubuntu covers Ubuntu &
# Debian, is_fedora covers RPM-based distros).  Higher-level functions
# such as "install_package" further abstract things in better ways.
#
# ``os_VENDOR`` - vendor name: ``Ubuntu``, ``Fedora``, etc
# ``os_RELEASE`` - major release: ``16.04`` (Ubuntu), ``23`` (Fedora)
# ``os_PACKAGE`` - package type: ``deb`` or ``rpm``
# ``os_CODENAME`` - vendor's codename for release: ``xenial``

declare -g os_VENDOR os_RELEASE os_PACKAGE os_CODENAME

# Make a *best effort* attempt to install lsb_release packages for the
# user if not available.  Note can't use generic install_package*
# because they depend on this!
function _ensure_lsb_release {
    if [[ -x $(command -v lsb_release 2>/dev/null) ]]; then
        return
    fi

    if [[ -x $(command -v apt-get 2>/dev/null) ]]; then
        sudo apt-get install -y lsb-release
    elif [[ -x $(command -v zypper 2>/dev/null) ]]; then
        # XXX: old code paths seem to have assumed SUSE platforms also
        # had "yum".  Keep this ordered above yum so we don't try to
        # install the rh package.  suse calls it just "lsb"
        sudo zypper -n install lsb
    elif [[ -x $(command -v dnf 2>/dev/null) ]]; then
        sudo dnf install -y redhat-lsb-core
    elif [[ -x $(command -v yum 2>/dev/null) ]]; then
        # all rh patforms (fedora, centos, rhel) have this pkg
        sudo yum install -y redhat-lsb-core
    else
        die $LINENO "Unable to find or auto-install lsb_release"
    fi
}

# GetOSVersion
#  Set the following variables:
#  - os_RELEASE
#  - os_CODENAME
#  - os_VENDOR
#  - os_PACKAGE
function GetOSVersion {
    # We only support distros that provide a sane lsb_release
    _ensure_lsb_release

    os_RELEASE=$(lsb_release -r -s)
    os_CODENAME=$(lsb_release -c -s)
    os_VENDOR=$(lsb_release -i -s)

    if [[ $os_VENDOR =~ (Debian|Ubuntu|LinuxMint) ]]; then
        os_PACKAGE="deb"
    else
        os_PACKAGE="rpm"
    fi

    typeset -xr os_VENDOR
    typeset -xr os_RELEASE
    typeset -xr os_PACKAGE
    typeset -xr os_CODENAME
}

# Translate the OS version values into common nomenclature
# Sets global ``DISTRO`` from the ``os_*`` values
declare -g DISTRO

function GetDistro {
    GetOSVersion
    if [[ "$os_VENDOR" =~ (Ubuntu) || "$os_VENDOR" =~ (Debian) || \
            "$os_VENDOR" =~ (LinuxMint) ]]; then
        # 'Everyone' refers to Ubuntu / Debian / Mint releases by
        # the code name adjective
        DISTRO=$os_CODENAME
    elif [[ "$os_VENDOR" =~ (Fedora) ]]; then
        # For Fedora, just use 'f' and the release
        DISTRO="f$os_RELEASE"
    elif [[ "$os_VENDOR" =~ (openSUSE) ]]; then
        DISTRO="opensuse-$os_RELEASE"
    elif [[ "$os_VENDOR" =~ (SUSE LINUX) ]]; then
        # just use major release
        DISTRO="sle${os_RELEASE%.*}"
    elif [[ "$os_VENDOR" =~ (Red.*Hat) || \
        "$os_VENDOR" =~ (CentOS) || \
        "$os_VENDOR" =~ (Scientific) || \
        "$os_VENDOR" =~ (OracleServer) || \
        "$os_VENDOR" =~ (Virtuozzo) ]]; then
        # Drop the . release as we assume it's compatible
        # XXX re-evaluate when we get RHEL10
        DISTRO="rhel${os_RELEASE::1}"
    elif [[ "$os_VENDOR" =~ (XenServer) ]]; then
        DISTRO="xs${os_RELEASE%.*}"
    elif [[ "$os_VENDOR" =~ (kvmibm) ]]; then
        DISTRO="${os_VENDOR}${os_RELEASE::1}"
    else
        # We can't make a good choice here.  Setting a sensible DISTRO
        # is part of the problem, but not the major issue -- we really
        # only use DISTRO in the code as a fine-filter.
        #
        # The bigger problem is categorising the system into one of
        # our two big categories as Ubuntu/Debian-ish or
        # Fedora/CentOS-ish.
        #
        # The setting of os_PACKAGE above is only set to "deb" based
        # on a hard-coded list of vendor names ... thus we will
        # default to thinking unknown distros are RPM based
        # (ie. is_ubuntu does not match).  But the platform will then
        # also not match in is_fedora, because that also has a list of
        # names.
        #
        # So, if you are reading this, getting your distro supported
        # is really about making sure it matches correctly in these
        # functions.  Then you can choose a sensible way to construct
        # DISTRO based on your distros release approach.
        die $LINENO "Unable to determine DISTRO, can not continue."
    fi
    typeset -xr DISTRO
}

# Utility function for checking machine architecture
# is_arch arch-type
function is_arch {
    [[ "$(uname -m)" == "$1" ]]
}

# Determine if current distribution is an Oracle distribution
# is_oraclelinux
function is_oraclelinux {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "OracleServer" ]
}


# Determine if current distribution is a Fedora-based distribution
# (Fedora, RHEL, CentOS, etc).
# is_fedora
function is_fedora {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "Fedora" ] || [ "$os_VENDOR" = "Red Hat" ] || \
        [ "$os_VENDOR" = "RedHatEnterpriseServer" ] || \
        [ "$os_VENDOR" = "CentOS" ] || [ "$os_VENDOR" = "OracleServer" ] || \
        [ "$os_VENDOR" = "Virtuozzo" ] || [ "$os_VENDOR" = "kvmibm" ]
}


# Determine if current distribution is a SUSE-based distribution
# (openSUSE, SLE).
# is_suse
function is_suse {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [[ "$os_VENDOR" =~ (openSUSE) || "$os_VENDOR" == "SUSE LINUX" ]]
}


# Determine if current distribution is an Ubuntu-based distribution
# It will also detect non-Ubuntu but Debian-based distros
# is_ubuntu
function is_ubuntu {
    if [[ -z "$os_PACKAGE" ]]; then
        GetOSVersion
    fi
    [ "$os_PACKAGE" = "deb" ]
}


# Git Functions
# =============

# Returns openstack release name for a given branch name
# ``get_release_name_from_branch branch-name``
function get_release_name_from_branch {
    local branch=$1
    if [[ $branch =~ "stable/" || $branch =~ "proposed/" ]]; then
        echo ${branch#*/}
    else
        echo "master"
    fi
}

# git clone only if directory doesn't exist already.  Since ``DEST`` might not
# be owned by the installation user, we create the directory and change the
# ownership to the proper user.
# Set global ``RECLONE=yes`` to simulate a clone when dest-dir exists
# Set global ``ERROR_ON_CLONE=True`` to abort execution with an error if the git repo
# does not exist (default is False, meaning the repo will be cloned).
# Uses globals ``ERROR_ON_CLONE``, ``OFFLINE``, ``RECLONE``
# git_clone remote dest-dir branch
function git_clone {
    local git_remote=$1
    local git_dest=$2
    local git_ref=$3
    local orig_dir
    orig_dir=$(pwd)
    local git_clone_flags=""

    RECLONE=$(trueorfalse False RECLONE)
    if [[ "${GIT_DEPTH}" -gt 0 ]]; then
        git_clone_flags="$git_clone_flags --depth $GIT_DEPTH"
    fi

    if [[ "$OFFLINE" = "True" ]]; then
        echo "Running in offline mode, clones already exist"
        # print out the results so we know what change was used in the logs
        cd $git_dest
        git show --oneline | head -1
        cd $orig_dir
        return
    fi

    if echo $git_ref | egrep -q "^refs"; then
        # If our branch name is a gerrit style refs/changes/...
        if [[ ! -d $git_dest ]]; then
            if [[ "$ERROR_ON_CLONE" = "True" ]]; then
                echo "The $git_dest project was not found; if this is a gate job, add"
                echo "the project to the \$PROJECTS variable in the job definition."
                die $LINENO "Cloning not allowed in this configuration"
            fi
            git_timed clone $git_clone_flags $git_remote $git_dest
        fi
        cd $git_dest
        git_timed fetch $git_remote $git_ref && git checkout FETCH_HEAD
    else
        # do a full clone only if the directory doesn't exist
        if [[ ! -d $git_dest ]]; then
            if [[ "$ERROR_ON_CLONE" = "True" ]]; then
                echo "The $git_dest project was not found; if this is a gate job, add"
                echo "the project to the \$PROJECTS variable in the job definition."
                die $LINENO "Cloning not allowed in this configuration"
            fi
            # '--branch' can also take tags
            git_timed clone $git_clone_flags $git_remote $git_dest --branch $git_ref
        elif [[ "$RECLONE" = "True" ]]; then
            # if it does exist then simulate what clone does if asked to RECLONE
            cd $git_dest
            # set the url to pull from and fetch
            git remote set-url origin $git_remote
            git_timed fetch origin
            # remove the existing ignored files (like pyc) as they cause breakage
            # (due to the py files having older timestamps than our pyc, so python
            # thinks the pyc files are correct using them)
            find $git_dest -name '*.pyc' -delete

            # handle git_ref accordingly to type (tag, branch)
            if [[ -n "`git show-ref refs/tags/$git_ref`" ]]; then
                git_update_tag $git_ref
            elif [[ -n "`git show-ref refs/heads/$git_ref`" ]]; then
                git_update_branch $git_ref
            elif [[ -n "`git show-ref refs/remotes/origin/$git_ref`" ]]; then
                git_update_remote_branch $git_ref
            else
                die $LINENO "$git_ref is neither branch nor tag"
            fi

        fi
    fi

    # print out the results so we know what change was used in the logs
    cd $git_dest
    git show --oneline | head -1
    cd $orig_dir
}

# A variation on git clone that lets us specify a project by it's
# actual name, like oslo.config. This is exceptionally useful in the
# library installation case
function git_clone_by_name {
    local name=$1
    local repo=${GITREPO[$name]}
    local dir=${GITDIR[$name]}
    local branch=${GITBRANCH[$name]}
    git_clone $repo $dir $branch
}


# git can sometimes get itself infinitely stuck with transient network
# errors or other issues with the remote end.  This wraps git in a
# timeout/retry loop and is intended to watch over non-local git
# processes that might hang.  GIT_TIMEOUT, if set, is passed directly
# to timeout(1); otherwise the default value of 0 maintains the status
# quo of waiting forever.
# usage: git_timed <git-command>
function git_timed {
    local count=0
    local timeout=0

    if [[ -n "${GIT_TIMEOUT}" ]]; then
        timeout=${GIT_TIMEOUT}
    fi

    time_start "git_timed"
    until timeout -s SIGINT ${timeout} git "$@"; do
        # 124 is timeout(1)'s special return code when it reached the
        # timeout; otherwise assume fatal failure
        if [[ $? -ne 124 ]]; then
            die $LINENO "git call failed: [git $@]"
        fi

        count=$(($count + 1))
        warn $LINENO "timeout ${count} for git call: [git $@]"
        if [ $count -eq 3 ]; then
            die $LINENO "Maximum of 3 git retries reached"
        fi
        sleep 5
    done
    time_stop "git_timed"
}

# git update using reference as a branch.
# git_update_branch ref
function git_update_branch {
    local git_branch=$1

    git checkout -f origin/$git_branch
    # a local branch might not exist
    git branch -D $git_branch || true
    git checkout -b $git_branch
}

# git update using reference as a branch.
# git_update_remote_branch ref
function git_update_remote_branch {
    local git_branch=$1

    git checkout -b $git_branch -t origin/$git_branch
}

# git update using reference as a tag. Be careful editing source at that repo
# as working copy will be in a detached mode
# git_update_tag ref
function git_update_tag {
    local git_tag=$1

    git tag -d $git_tag
    # fetching given tag only
    git_timed fetch origin tag $git_tag
    git checkout -f $git_tag
}


# OpenStack Functions
# ===================

# Get the default value for HOST_IP
# get_default_host_ip fixed_range floating_range host_ip_iface host_ip
function get_default_host_ip {
    local fixed_range=$1
    local floating_range=$2
    local host_ip_iface=$3
    local host_ip=$4
    local af=$5

    # Search for an IP unless an explicit is set by ``HOST_IP`` environment variable
    if [ -z "$host_ip" -o "$host_ip" == "dhcp" ]; then
        host_ip=""
        # Find the interface used for the default route
        host_ip_iface=${host_ip_iface:-$(ip -f $af route | awk '/default/ {print $5}' | head -1)}
        local host_ips
        host_ips=$(LC_ALL=C ip -f $af addr show ${host_ip_iface} | sed /temporary/d |awk /$af'/ {split($2,parts,"/");  print parts[1]}')
        local ip
        for ip in $host_ips; do
            # Attempt to filter out IP addresses that are part of the fixed and
            # floating range. Note that this method only works if the ``netaddr``
            # python library is installed. If it is not installed, an error
            # will be printed and the first IP from the interface will be used.
            # If that is not correct set ``HOST_IP`` in ``localrc`` to the correct
            # address.
            if [[ "$af" == "inet6" ]]; then
                host_ip=$ip
                break;
            fi
            if ! (address_in_net $ip $fixed_range || address_in_net $ip $floating_range); then
                host_ip=$ip
                break;
            fi
        done
    fi
    echo $host_ip
}

# Generates hex string from ``size`` byte of pseudo random data
# generate_hex_string size
function generate_hex_string {
    local size=$1
    hexdump -n "$size" -v -e '/1 "%02x"' /dev/urandom
}

# Grab a numbered field from python prettytable output
# Fields are numbered starting with 1
# Reverse syntax is supported: -1 is the last field, -2 is second to last, etc.
# get_field field-number
function get_field {
    local data field
    while read data; do
        if [ "$1" -lt 0 ]; then
            field="(\$(NF$1))"
        else
            field="\$$(($1 + 1))"
        fi
        echo "$data" | awk -F'[ \t]*\\|[ \t]*' "{print $field}"
    done
}

# install default policy
# copy over a default policy.json and policy.d for projects
function install_default_policy {
    local project=$1
    local project_uc
    project_uc=$(echo $1|tr a-z A-Z)
    local conf_dir="${project_uc}_CONF_DIR"
    # eval conf dir to get the variable
    conf_dir="${!conf_dir}"
    local project_dir="${project_uc}_DIR"
    # eval project dir to get the variable
    project_dir="${!project_dir}"
    local sample_conf_dir="${project_dir}/etc/${project}"
    local sample_policy_dir="${project_dir}/etc/${project}/policy.d"

    # first copy any policy.json
    cp -p $sample_conf_dir/policy.json $conf_dir
    # then optionally copy over policy.d
    if [[ -d $sample_policy_dir ]]; then
        cp -r $sample_policy_dir $conf_dir/policy.d
    fi
}

# Add a policy to a policy.json file
# Do nothing if the policy already exists
# ``policy_add policy_file policy_name policy_permissions``
function policy_add {
    local policy_file=$1
    local policy_name=$2
    local policy_perm=$3

    if grep -q ${policy_name} ${policy_file}; then
        echo "Policy ${policy_name} already exists in ${policy_file}"
        return
    fi

    # Add a terminating comma to policy lines without one
    # Remove the closing '}' and all lines following to the end-of-file
    local tmpfile
    tmpfile=$(mktemp)
    uniq ${policy_file} | sed -e '
        s/]$/],/
        /^[}]/,$d
    ' > ${tmpfile}

    # Append policy and closing brace
    echo "    \"${policy_name}\": ${policy_perm}" >>${tmpfile}
    echo "}" >>${tmpfile}

    mv ${tmpfile} ${policy_file}
}

# Gets or creates a domain
# Usage: get_or_create_domain <name> <description>
function get_or_create_domain {
    local domain_id
    # Gets domain id
    domain_id=$(
        # Gets domain id
        openstack domain show $1 \
            -f value -c id 2>/dev/null ||
        # Creates new domain
        openstack domain create $1 \
            --description "$2" \
            -f value -c id
    )
    echo $domain_id
}

# Gets or creates group
# Usage: get_or_create_group <groupname> <domain> [<description>]
function get_or_create_group {
    local desc="${3:-}"
    local group_id
    # Gets group id
    group_id=$(
        # Creates new group with --or-show
        openstack group create $1 \
            --domain $2 --description "$desc" --or-show \
            -f value -c id
    )
    echo $group_id
}

# Gets or creates user
# Usage: get_or_create_user <username> <password> <domain> [<email>]
function get_or_create_user {
    local user_id
    if [[ ! -z "$4" ]]; then
        local email="--email=$4"
    else
        local email=""
    fi
    # Gets user id
    user_id=$(
        # Creates new user with --or-show
        openstack user create \
            $1 \
            --password "$2" \
            --domain=$3 \
            $email \
            --or-show \
            -f value -c id
    )
    echo $user_id
}

# Gets or creates project
# Usage: get_or_create_project <name> <domain>
function get_or_create_project {
    local project_id
    project_id=$(
        # Creates new project with --or-show
        openstack project create $1 \
            --domain=$2 \
            --or-show -f value -c id
    )
    echo $project_id
}

# Gets or creates role
# Usage: get_or_create_role <name>
function get_or_create_role {
    local role_id
    role_id=$(
        # Creates role with --or-show
        openstack role create $1 \
            --or-show -f value -c id
    )
    echo $role_id
}

# Returns the domain parts of a function call if present
# Usage: _get_domain_args [<user_domain> <project_domain>]
function _get_domain_args {
    local domain
    domain=""

    if [[ -n "$1" ]]; then
        domain="$domain --user-domain $1"
    fi
    if [[ -n "$2" ]]; then
        domain="$domain --project-domain $2"
    fi

    echo $domain
}

# Gets or adds user role to project
# Usage: get_or_add_user_project_role <role> <user> <project> [<user_domain> <project_domain>]
function get_or_add_user_project_role {
    local user_role_id

    domain_args=$(_get_domain_args $4 $5)

    # Gets user role id
    user_role_id=$(openstack role assignment list \
        --user $2 \
        --project $3 \
        $domain_args \
        | grep " $1 " | get_field 1)
    if [[ -z "$user_role_id" ]]; then
        # Adds role to user and get it
        openstack role add $1 \
            --user $2 \
            --project $3 \
            $domain_args
        user_role_id=$(openstack role assignment list \
            --user $2 \
            --project $3 \
            $domain_args \
            | grep " $1 " | get_field 1)
    fi
    echo $user_role_id
}

# Gets or adds user role to domain
# Usage: get_or_add_user_domain_role <role> <user> <domain>
function get_or_add_user_domain_role {
    local user_role_id
    # Gets user role id
    user_role_id=$(openstack role assignment list \
        --user $2 \
        --domain $3 \
        | grep " $1 " | get_field 1)
    if [[ -z "$user_role_id" ]]; then
        # Adds role to user and get it
        openstack role add $1 \
            --user $2 \
            --domain $3
        user_role_id=$(openstack role assignment list \
            --user $2 \
            --domain $3 \
            | grep " $1 " | get_field 1)
    fi
    echo $user_role_id
}

# Gets or adds group role to project
# Usage: get_or_add_group_project_role <role> <group> <project>
function get_or_add_group_project_role {
    local group_role_id
    # Gets group role id
    group_role_id=$(openstack role assignment list \
        --group $2 \
        --project $3 \
        -f value)
    if [[ -z "$group_role_id" ]]; then
        # Adds role to group and get it
        openstack role add $1 \
            --group $2 \
            --project $3
        group_role_id=$(openstack role assignment list \
            --group $2 \
            --project $3 \
            -f value)
    fi
    echo $group_role_id
}

# Gets or creates service
# Usage: get_or_create_service <name> <type> <description>
function get_or_create_service {
    local service_id
    # Gets service id
    service_id=$(
        # Gets service id
        openstack service show $2 -f value -c id 2>/dev/null ||
        # Creates new service if not exists
        openstack service create \
            $2 \
            --name $1 \
            --description="$3" \
            -f value -c id
    )
    echo $service_id
}

# Create an endpoint with a specific interface
# Usage: _get_or_create_endpoint_with_interface <service> <interface> <url> <region>
function _get_or_create_endpoint_with_interface {
    local endpoint_id
    endpoint_id=$(openstack endpoint list \
        --service $1 \
        --interface $2 \
        --region $4 \
        -c ID -f value)
    if [[ -z "$endpoint_id" ]]; then
        # Creates new endpoint
        endpoint_id=$(openstack endpoint create \
            $1 $2 $3 --region $4 -f value -c id)
    fi

    echo $endpoint_id
}

# Gets or creates endpoint
# Usage: get_or_create_endpoint <service> <region> <publicurl> [adminurl] [internalurl]
function get_or_create_endpoint {
    # NOTE(jamielennnox): when converting to v3 endpoint creation we go from
    # creating one endpoint with multiple urls to multiple endpoints each with
    # a different interface.  To maintain the existing function interface we
    # create 3 endpoints and return the id of the public one. In reality
    # returning the public id will not make a lot of difference as there are no
    # scenarios currently that use the returned id. Ideally this behaviour
    # should be pushed out to the service setups and let them create the
    # endpoints they need.
    local public_id
    public_id=$(_get_or_create_endpoint_with_interface $1 public $3 $2)
    # only create admin/internal urls if provided content for them
    if [[ -n "$4" ]]; then
        _get_or_create_endpoint_with_interface $1 admin $4 $2
    fi
    if [[ -n "$5" ]]; then
        _get_or_create_endpoint_with_interface $1 internal $5 $2
    fi
    # return the public id to indicate success, and this is the endpoint most likely wanted
    echo $public_id
}

# Get a URL from the identity service
# Usage: get_endpoint_url <service> <interface>
function get_endpoint_url {
    echo $(openstack endpoint list \
            --service $1 --interface $2 \
            -c URL -f value)
}

# check if we are using ironic with hardware
# TODO(jroll) this is a kludge left behind when ripping ironic code
# out of tree, as it is used by nova and neutron.
# figure out a way to refactor nova/neutron code to eliminate this
function is_ironic_hardware {
    is_service_enabled ironic && [[ "$IRONIC_IS_HARDWARE" == "True" ]] && return 0
    return 1
}


# Package Functions
# =================

# _get_package_dir
function _get_package_dir {
    local base_dir=$1
    local pkg_dir

    if [[ -z "$base_dir" ]]; then
        base_dir=$FILES
    fi
    if is_ubuntu; then
        pkg_dir=$base_dir/debs
    elif is_fedora; then
        pkg_dir=$base_dir/rpms
    elif is_suse; then
        pkg_dir=$base_dir/rpms-suse
    else
        exit_distro_not_supported "list of packages"
    fi
    echo "$pkg_dir"
}

# Wrapper for ``apt-get update`` to try multiple times on the update
# to address bad package mirrors (which happen all the time).
function apt_get_update {
    # only do this once per run
    if [[ "$REPOS_UPDATED" == "True" && "$RETRY_UPDATE" != "True" ]]; then
        return
    fi

    # bail if we are offline
    [[ "$OFFLINE" = "True" ]] && return

    local sudo="sudo"
    [[ "$(id -u)" = "0" ]] && sudo="env"

    # time all the apt operations
    time_start "apt-get-update"

    local proxies="http_proxy=${http_proxy:-} https_proxy=${https_proxy:-} no_proxy=${no_proxy:-} "
    local update_cmd="$sudo $proxies apt-get update"
    if ! timeout 300 sh -c "while ! $update_cmd; do sleep 30; done"; then
        die $LINENO "Failed to update apt repos, we're dead now"
    fi

    REPOS_UPDATED=True
    # stop the clock
    time_stop "apt-get-update"
}

# Wrapper for ``apt-get`` to set cache and proxy environment variables
# Uses globals ``OFFLINE``, ``*_proxy``
# apt_get operation package [package ...]
function apt_get {
    local xtrace result
    xtrace=$(set +o | grep xtrace)
    set +o xtrace

    [[ "$OFFLINE" = "True" || -z "$@" ]] && return
    local sudo="sudo"
    [[ "$(id -u)" = "0" ]] && sudo="env"

    # time all the apt operations
    time_start "apt-get"

    $xtrace

    $sudo DEBIAN_FRONTEND=noninteractive \
        http_proxy=${http_proxy:-} https_proxy=${https_proxy:-} \
        no_proxy=${no_proxy:-} \
        apt-get --option "Dpkg::Options::=--force-confold" --assume-yes "$@" < /dev/null
    result=$?

    # stop the clock
    time_stop "apt-get"
    return $result
}

function _parse_package_files {
    local files_to_parse=$@

    if [[ -z "$DISTRO" ]]; then
        GetDistro
    fi

    for fname in ${files_to_parse}; do
        local OIFS line package distros distro
        [[ -e $fname ]] || continue

        OIFS=$IFS
        IFS=$'\n'
        for line in $(<${fname}); do
            if [[ $line =~ "NOPRIME" ]]; then
                continue
            fi

            # Assume we want this package; free-form
            # comments allowed after a #
            package=${line%%#*}
            inst_pkg=1

            # Look for # dist:xxx in comment
            if [[ $line =~ (.*)#.*dist:([^ ]*) ]]; then
                # We are using BASH regexp matching feature.
                package=${BASH_REMATCH[1]}
                distros=${BASH_REMATCH[2]}
                # In bash ${VAR,,} will lowercase VAR
                # Look for a match in the distro list
                if [[ ! ${distros,,} =~ ${DISTRO,,} ]]; then
                    # If no match then skip this package
                    inst_pkg=0
                fi
            fi

            # Look for # not:xxx in comment
            if [[ $line =~ (.*)#.*not:([^ ]*) ]]; then
                # We are using BASH regexp matching feature.
                package=${BASH_REMATCH[1]}
                distros=${BASH_REMATCH[2]}
                # In bash ${VAR,,} will lowercase VAR
                # Look for a match in the distro list
                if [[ ${distros,,} =~ ${DISTRO,,} ]]; then
                    # If match then skip this package
                    inst_pkg=0
                fi
            fi

            if [[ $inst_pkg = 1 ]]; then
                echo $package
            fi
        done
        IFS=$OIFS
    done
}

# get_packages() collects a list of package names of any type from the
# prerequisite files in ``files/{debs|rpms}``.  The list is intended
# to be passed to a package installer such as apt or yum.
#
# Only packages required for the services in 1st argument will be
# included.  Two bits of metadata are recognized in the prerequisite files:
#
# - ``# NOPRIME`` defers installation to be performed later in `stack.sh`
# - ``# dist:DISTRO`` or ``dist:DISTRO1,DISTRO2`` limits the selection
#   of the package to the distros listed.  The distro names are case insensitive.
# - ``# not:DISTRO`` or ``not:DISTRO1,DISTRO2`` limits the selection
#   of the package to the distros not listed. The distro names are case insensitive.
function get_packages {
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local services=$@
    local package_dir
    package_dir=$(_get_package_dir)
    local file_to_parse=""
    local service=""

    if [ $# -ne 1 ]; then
        die $LINENO "get_packages takes a single, comma-separated argument"
    fi

    if [[ -z "$package_dir" ]]; then
        echo "No package directory supplied"
        return 1
    fi
    for service in ${services//,/ }; do
        # Allow individual services to specify dependencies
        if [[ -e ${package_dir}/${service} ]]; then
            file_to_parse="${file_to_parse} ${package_dir}/${service}"
        fi
        # NOTE(sdague) n-api needs glance for now because that's where
        # glance client is
        if [[ $service == n-api ]]; then
            if [[ ! $file_to_parse =~ $package_dir/nova ]]; then
                file_to_parse="${file_to_parse} ${package_dir}/nova"
            fi
            if [[ ! $file_to_parse =~ $package_dir/glance ]]; then
                file_to_parse="${file_to_parse} ${package_dir}/glance"
            fi
        elif [[ $service == c-* ]]; then
            if [[ ! $file_to_parse =~ $package_dir/cinder ]]; then
                file_to_parse="${file_to_parse} ${package_dir}/cinder"
            fi
        elif [[ $service == s-* ]]; then
            if [[ ! $file_to_parse =~ $package_dir/swift ]]; then
                file_to_parse="${file_to_parse} ${package_dir}/swift"
            fi
        elif [[ $service == n-* ]]; then
            if [[ ! $file_to_parse =~ $package_dir/nova ]]; then
                file_to_parse="${file_to_parse} ${package_dir}/nova"
            fi
        elif [[ $service == g-* ]]; then
            if [[ ! $file_to_parse =~ $package_dir/glance ]]; then
                file_to_parse="${file_to_parse} ${package_dir}/glance"
            fi
        elif [[ $service == key* ]]; then
            if [[ ! $file_to_parse =~ $package_dir/keystone ]]; then
                file_to_parse="${file_to_parse} ${package_dir}/keystone"
            fi
        elif [[ $service == q-* ]]; then
            if [[ ! $file_to_parse =~ $package_dir/neutron ]]; then
                file_to_parse="${file_to_parse} ${package_dir}/neutron"
            fi
        elif [[ $service == ir-* ]]; then
            if [[ ! $file_to_parse =~ $package_dir/ironic ]]; then
                file_to_parse="${file_to_parse} ${package_dir}/ironic"
            fi
        fi
    done
    echo "$(_parse_package_files $file_to_parse)"
    $xtrace
}

# get_plugin_packages() collects a list of package names of any type from a
# plugin's prerequisite files in ``$PLUGIN/devstack/files/{debs|rpms}``.  The
# list is intended to be passed to a package installer such as apt or yum.
#
# Only packages required for enabled and collected plugins will included.
#
# The same metadata used in the main DevStack prerequisite files may be used
# in these prerequisite files, see get_packages() for more info.
function get_plugin_packages {
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local files_to_parse=""
    local package_dir=""
    for plugin in ${DEVSTACK_PLUGINS//,/ }; do
        package_dir="$(_get_package_dir ${GITDIR[$plugin]}/devstack/files)"
        files_to_parse+=" $package_dir/$plugin"
    done
    echo "$(_parse_package_files $files_to_parse)"
    $xtrace
}

# Distro-agnostic package installer
# Uses globals ``NO_UPDATE_REPOS``, ``REPOS_UPDATED``, ``RETRY_UPDATE``
# install_package package [package ...]
function update_package_repo {
    NO_UPDATE_REPOS=${NO_UPDATE_REPOS:-False}
    REPOS_UPDATED=${REPOS_UPDATED:-False}
    RETRY_UPDATE=${RETRY_UPDATE:-False}

    if [[ "$NO_UPDATE_REPOS" = "True" ]]; then
        return 0
    fi

    if is_ubuntu; then
        apt_get_update
    fi
}

function real_install_package {
    if is_ubuntu; then
        apt_get install "$@"
    elif is_fedora; then
        yum_install "$@"
    elif is_suse; then
        zypper_install "$@"
    else
        exit_distro_not_supported "installing packages"
    fi
}

# Distro-agnostic package installer
# install_package package [package ...]
function install_package {
    update_package_repo
    if ! real_install_package "$@"; then
        RETRY_UPDATE=True update_package_repo && real_install_package "$@"
    fi
}

# Distro-agnostic function to tell if a package is installed
# is_package_installed package [package ...]
function is_package_installed {
    if [[ -z "$@" ]]; then
        return 1
    fi

    if [[ -z "$os_PACKAGE" ]]; then
        GetOSVersion
    fi

    if [[ "$os_PACKAGE" = "deb" ]]; then
        dpkg -s "$@" > /dev/null 2> /dev/null
    elif [[ "$os_PACKAGE" = "rpm" ]]; then
        rpm --quiet -q "$@"
    else
        exit_distro_not_supported "finding if a package is installed"
    fi
}

# Distro-agnostic package uninstaller
# uninstall_package package [package ...]
function uninstall_package {
    if is_ubuntu; then
        apt_get purge "$@"
    elif is_fedora; then
        sudo ${YUM:-yum} remove -y "$@" ||:
    elif is_suse; then
        sudo zypper remove -y "$@" ||:
    else
        exit_distro_not_supported "uninstalling packages"
    fi
}

# Wrapper for ``yum`` to set proxy environment variables
# Uses globals ``OFFLINE``, ``*_proxy``, ``YUM``
# yum_install package [package ...]
function yum_install {
    local result parse_yum_result

    [[ "$OFFLINE" = "True" ]] && return

    time_start "yum_install"

    # This is a bit tricky, because yum -y assumes missing or failed
    # packages are OK (see [1]).  We want devstack to stop if we are
    # installing missing packages.
    #
    # Thus we manually match on the output (stack.sh runs in a fixed
    # locale, so lang shouldn't change).
    #
    # If yum returns !0, we echo the result as "YUM_FAILED" and return
    # that from the awk (we're subverting -e with this trick).
    # Otherwise we use awk to look for failure strings and return "2"
    # to indicate a terminal failure.
    #
    # [1] https://bugzilla.redhat.com/show_bug.cgi?id=965567
    parse_yum_result='              \
        BEGIN { result=0 }          \
        /^YUM_FAILED/ { result=$2 } \
        /^No package/ { result=2 }  \
        /^Failed:/    { result=2 }  \
        //{ print }                 \
        END { exit result }'
    (sudo_with_proxies "${YUM:-yum}" install -y "$@" 2>&1 || echo YUM_FAILED $?) \
        | awk "$parse_yum_result" && result=$? || result=$?

    time_stop "yum_install"

    # if we return 1, then the wrapper functions will run an update
    # and try installing the package again as a defense against bad
    # mirrors.  This can hide failures, especially when we have
    # packages that are in the "Failed:" section because their rpm
    # install scripts failed to run correctly (in this case, the
    # package looks installed, so when the retry happens we just think
    # the package is OK, and incorrectly continue on).
    if [ "$result" == 2 ]; then
        die "Detected fatal package install failure"
    fi

    return "$result"
}

# zypper wrapper to set arguments correctly
# Uses globals ``OFFLINE``, ``*_proxy``
# zypper_install package [package ...]
function zypper_install {
    [[ "$OFFLINE" = "True" ]] && return
    local sudo="sudo"
    [[ "$(id -u)" = "0" ]] && sudo="env"
    $sudo http_proxy="${http_proxy:-}" https_proxy="${https_proxy:-}" \
        no_proxy="${no_proxy:-}" \
        zypper --non-interactive install --auto-agree-with-licenses "$@"
}


# Process Functions
# =================

# _run_process() is designed to be backgrounded by run_process() to simulate a
# fork.  It includes the dirty work of closing extra filehandles and preparing log
# files to produce the same logs as screen_it().  The log filename is derived
# from the service name.
# Uses globals ``CURRENT_LOG_TIME``, ``LOGDIR``, ``SCREEN_LOGDIR``, ``SCREEN_NAME``, ``SERVICE_DIR``
# If an optional group is provided sg will be used to set the group of
# the command.
# _run_process service "command-line" [group]
function _run_process {
    # disable tracing through the exec redirects, it's just confusing in the logs.
    xtrace=$(set +o | grep xtrace)
    set +o xtrace

    local service=$1
    local command="$2"
    local group=$3

    # Undo logging redirections and close the extra descriptors
    exec 1>&3
    exec 2>&3
    exec 3>&-
    exec 6>&-

    local logfile="${service}.log.${CURRENT_LOG_TIME}"
    local real_logfile="${LOGDIR}/${logfile}"
    if [[ -n ${LOGDIR} ]]; then
        exec 1>&"$real_logfile" 2>&1
        bash -c "cd '$LOGDIR' && ln -sf '$logfile' ${service}.log"
        if [[ -n ${SCREEN_LOGDIR} ]]; then
            # Drop the backward-compat symlink
            ln -sf "$real_logfile" ${SCREEN_LOGDIR}/screen-${service}.log
        fi

        # TODO(dtroyer): Hack to get stdout from the Python interpreter for the logs.
        export PYTHONUNBUFFERED=1
    fi

    # reenable xtrace before we do *real* work
    $xtrace

    # Run under ``setsid`` to force the process to become a session and group leader.
    # The pid saved can be used with pkill -g to get the entire process group.
    if [[ -n "$group" ]]; then
        setsid sg $group "$command" & echo $! >$SERVICE_DIR/$SCREEN_NAME/$service.pid
    else
        setsid $command & echo $! >$SERVICE_DIR/$SCREEN_NAME/$service.pid
    fi

    # Just silently exit this process
    exit 0
}

function write_user_unit_file {
    local service=$1
    local command="$2"
    local group=$3
    local user=$4
    local extra=""
    if [[ -n "$group" ]]; then
        extra="Group=$group"
    fi
    local unitfile="$SYSTEMD_DIR/$service"
    mkdir -p $SYSTEMD_DIR

    iniset -sudo $unitfile "Unit" "Description" "Devstack $service"
    iniset -sudo $unitfile "Service" "User" "$user"
    iniset -sudo $unitfile "Service" "ExecStart" "$command"
    if [[ -n "$group" ]]; then
        iniset -sudo $unitfile "Service" "Group" "$group"
    fi
    iniset -sudo $unitfile "Install" "WantedBy" "multi-user.target"

    # changes to existing units sometimes need a refresh
    $SYSTEMCTL daemon-reload
}

function write_uwsgi_user_unit_file {
    local service=$1
    local command="$2"
    local group=$3
    local user=$4
    local unitfile="$SYSTEMD_DIR/$service"
    mkdir -p $SYSTEMD_DIR

    iniset -sudo $unitfile "Unit" "Description" "Devstack $service"
    iniset -sudo $unitfile "Service" "SyslogIdentifier" "$service"
    iniset -sudo $unitfile "Service" "User" "$user"
    iniset -sudo $unitfile "Service" "ExecStart" "$command"
    iniset -sudo $unitfile "Service" "Type" "notify"
    iniset -sudo $unitfile "Service" "KillSignal" "SIGQUIT"
    iniset -sudo $unitfile "Service" "Restart" "Always"
    iniset -sudo $unitfile "Service" "NotifyAccess" "all"
    iniset -sudo $unitfile "Service" "RestartForceExitStatus" "100"

    if [[ -n "$group" ]]; then
        iniset -sudo $unitfile "Service" "Group" "$group"
    fi
    iniset -sudo $unitfile "Install" "WantedBy" "multi-user.target"

    # changes to existing units sometimes need a refresh
    $SYSTEMCTL daemon-reload
}

function _common_systemd_pitfalls {
    local cmd=$1
    # do some sanity checks on $cmd to see things we don't expect to work

    if [[ "$cmd" =~ "sudo" ]]; then
        local msg=<<EOF
You are trying to use run_process with sudo, this is not going to work under systemd.

If you need to run a service as a user other than $STACK_USER call it with:

   run_process \$name \$cmd \$group \$user
EOF
        die $LINENO $msg
    fi

    if [[ ! "$cmd" =~ ^/ ]]; then
        local msg=<<EOF
The cmd="$cmd" does not start with an absolute path. It will fail to
start under systemd.

Please update your run_process stanza to have an absolute path.
EOF
        die $LINENO $msg
    fi

}

# Helper function to build a basic unit file and run it under systemd.
function _run_under_systemd {
    local service=$1
    local command="$2"
    local cmd=$command
    # sanity check the command
    _common_systemd_pitfalls "$cmd"

    local systemd_service="devstack@$service.service"
    local group=$3
    local user=${4:-$STACK_USER}
    if [[ "$command" =~ "uwsgi" ]] ; then
        write_uwsgi_user_unit_file $systemd_service "$cmd" "$group" "$user"
    else
        write_user_unit_file $systemd_service "$cmd" "$group" "$user"
    fi

    $SYSTEMCTL enable $systemd_service
    $SYSTEMCTL start $systemd_service
}

# Helper to remove the ``*.failure`` files under ``$SERVICE_DIR/$SCREEN_NAME``.
# This is used for ``service_check`` when all the ``screen_it`` are called finished
# Uses globals ``SCREEN_NAME``, ``SERVICE_DIR``
# init_service_check
function init_service_check {
    SCREEN_NAME=${SCREEN_NAME:-stack}
    SERVICE_DIR=${SERVICE_DIR:-${DEST}/status}

    if [[ ! -d "$SERVICE_DIR/$SCREEN_NAME" ]]; then
        mkdir -p "$SERVICE_DIR/$SCREEN_NAME"
    fi

    rm -f "$SERVICE_DIR/$SCREEN_NAME"/*.failure
}

# Find out if a process exists by partial name.
# is_running name
function is_running {
    local name=$1
    ps auxw | grep -v grep | grep ${name} > /dev/null
    local exitcode=$?
    # some times I really hate bash reverse binary logic
    return $exitcode
}

# Run a single service under screen or directly
# If the command includes shell metachatacters (;<>*) it must be run using a shell
# If an optional group is provided sg will be used to run the
# command as that group.
# Uses globals ``USE_SCREEN``
# run_process service "command-line" [group] [user]
function run_process {
    local service=$1
    local command="$2"
    local group=$3
    local user=$4

    local name=$service

    time_start "run_process"
    if is_service_enabled $service; then
        if [[ "$USE_SYSTEMD" = "True" ]]; then
            _run_under_systemd "$name" "$command" "$group" "$user"
        elif [[ "$USE_SCREEN" = "True" ]]; then
            if [[ "$user" == "root" ]]; then
                command="sudo $command"
            fi
            screen_process "$name" "$command" "$group"
        else
            # Spawn directly without screen
            if [[ "$user" == "root" ]]; then
                command="sudo $command"
            fi
            _run_process "$name" "$command" "$group" &
        fi
    fi
    time_stop "run_process"
}

# Helper to launch a process in a named screen
# Uses globals ``CURRENT_LOG_TIME``, ```LOGDIR``, ``SCREEN_LOGDIR``, `SCREEN_NAME``,
# ``SERVICE_DIR``, ``SCREEN_IS_LOGGING``
# screen_process name "command-line" [group]
# Run a command in a shell in a screen window, if an optional group
# is provided, use sg to set the group of the command.
function screen_process {
    local name=$1
    local command="$2"
    local group=$3

    SCREEN_NAME=${SCREEN_NAME:-stack}
    SERVICE_DIR=${SERVICE_DIR:-${DEST}/status}

    screen -S $SCREEN_NAME -X screen -t $name

    local logfile="${name}.log.${CURRENT_LOG_TIME}"
    local real_logfile="${LOGDIR}/${logfile}"
    echo "LOGDIR: $LOGDIR"
    echo "SCREEN_LOGDIR: $SCREEN_LOGDIR"
    echo "log: $real_logfile"
    if [[ -n ${LOGDIR} ]]; then
        if [[ "$SCREEN_IS_LOGGING" == "True" ]]; then
            screen -S $SCREEN_NAME -p $name -X logfile "$real_logfile"
            screen -S $SCREEN_NAME -p $name -X log on
        fi
        # If logging isn't active then avoid a broken symlink
        touch "$real_logfile"
        bash -c "cd '$LOGDIR' && ln -sf '$logfile' ${name}.log"
        if [[ -n ${SCREEN_LOGDIR} ]]; then
            # Drop the backward-compat symlink
            ln -sf "$real_logfile" ${SCREEN_LOGDIR}/screen-${1}.log
        fi
    fi

    # sleep to allow bash to be ready to be send the command - we are
    # creating a new window in screen and then sends characters, so if
    # bash isn't running by the time we send the command, nothing
    # happens.  This sleep was added originally to handle gate runs
    # where we needed this to be at least 3 seconds to pass
    # consistently on slow clouds. Now this is configurable so that we
    # can determine a reasonable value for the local case which should
    # be much smaller.
    sleep ${SCREEN_SLEEP:-3}

    NL=`echo -ne '\015'`
    # This fun command does the following:
    # - the passed server command is backgrounded
    # - the pid of the background process is saved in the usual place
    # - the server process is brought back to the foreground
    # - if the server process exits prematurely the fg command errors
    # and a message is written to stdout and the process failure file
    #
    # The pid saved can be used in stop_process() as a process group
    # id to kill off all child processes
    if [[ -n "$group" ]]; then
        command="sg $group '$command'"
    fi

    # Append the process to the screen rc file
    screen_rc "$name" "$command"

    screen -S $SCREEN_NAME -p $name -X stuff "$command & echo \$! >$SERVICE_DIR/$SCREEN_NAME/${name}.pid; fg || echo \"$name failed to start. Exit code: \$?\" | tee \"$SERVICE_DIR/$SCREEN_NAME/${name}.failure\"$NL"
}

# Screen rc file builder
# Uses globals ``SCREEN_NAME``, ``SCREENRC``, ``SCREEN_IS_LOGGING``
# screen_rc service "command-line"
function screen_rc {
    SCREEN_NAME=${SCREEN_NAME:-stack}
    SCREENRC=$TOP_DIR/$SCREEN_NAME-screenrc
    if [[ ! -e $SCREENRC ]]; then
        # Name the screen session
        echo "sessionname $SCREEN_NAME" > $SCREENRC
        # Set a reasonable statusbar
        echo "hardstatus alwayslastline '$SCREEN_HARDSTATUS'" >> $SCREENRC
        # Some distributions override PROMPT_COMMAND for the screen terminal type - turn that off
        echo "setenv PROMPT_COMMAND /bin/true" >> $SCREENRC
        echo "screen -t shell bash" >> $SCREENRC
    fi
    # If this service doesn't already exist in the screenrc file
    if ! grep $1 $SCREENRC 2>&1 > /dev/null; then
        NL=`echo -ne '\015'`
        echo "screen -t $1 bash" >> $SCREENRC
        echo "stuff \"$2$NL\"" >> $SCREENRC

        if [[ -n ${LOGDIR} ]] && [[ "$SCREEN_IS_LOGGING" == "True" ]]; then
            echo "logfile ${LOGDIR}/${1}.log.${CURRENT_LOG_TIME}" >>$SCREENRC
            echo "log on" >>$SCREENRC
        fi
    fi
}

# Stop a service in screen
# If a PID is available use it, kill the whole process group via TERM
# If screen is being used kill the screen window; this will catch processes
# that did not leave a PID behind
# Uses globals ``SCREEN_NAME``, ``SERVICE_DIR``
# screen_stop_service service
function screen_stop_service {
    local service=$1

    SCREEN_NAME=${SCREEN_NAME:-stack}
    SERVICE_DIR=${SERVICE_DIR:-${DEST}/status}

    if is_service_enabled $service; then
        # Clean up the screen window
        screen -S $SCREEN_NAME -p $service -X kill || true
    fi
}

# Stop a service process
# If a PID is available use it, kill the whole process group via TERM
# If screen is being used kill the screen window; this will catch processes
# that did not leave a PID behind
# Uses globals ``SERVICE_DIR``, ``USE_SCREEN``
# stop_process service
function stop_process {
    local service=$1

    SERVICE_DIR=${SERVICE_DIR:-${DEST}/status}

    if is_service_enabled $service; then
        # Only do this for units which appear enabled, this also
        # catches units that don't really exist for cases like
        # keystone without a failure.
        if $SYSTEMCTL is-enabled devstack@$service.service; then
            $SYSTEMCTL stop devstack@$service.service
            $SYSTEMCTL disable devstack@$service.service
        fi

        if [[ -r $SERVICE_DIR/$SCREEN_NAME/$service.pid ]]; then
            pkill -g $(cat $SERVICE_DIR/$SCREEN_NAME/$service.pid)
            # oslo.service tends to stop actually shutting down
            # reliably in between releases because someone believes it
            # is dying too early due to some inflight work they
            # have. This is a tension. It happens often enough we're
            # going to just account for it in devstack and assume it
            # doesn't work.
            #
            # Set OSLO_SERVICE_WORKS=True to skip this block
            if [[ -z "$OSLO_SERVICE_WORKS" ]]; then
                # TODO(danms): Remove this double-kill when we have
                # this fixed in all services:
                # https://bugs.launchpad.net/oslo-incubator/+bug/1446583
                sleep 1
                # /bin/true because pkill on a non existent process returns an error
                pkill -g $(cat $SERVICE_DIR/$SCREEN_NAME/$service.pid) || /bin/true
            fi
            rm $SERVICE_DIR/$SCREEN_NAME/$service.pid
        fi
        if [[ "$USE_SCREEN" = "True" ]]; then
            # Clean up the screen window
            screen_stop_service $service
        fi
    fi
}

# Helper to get the status of each running service
# Uses globals ``SCREEN_NAME``, ``SERVICE_DIR``
# service_check
function service_check {
    local service
    local failures
    SCREEN_NAME=${SCREEN_NAME:-stack}
    SERVICE_DIR=${SERVICE_DIR:-${DEST}/status}


    if [[ ! -d "$SERVICE_DIR/$SCREEN_NAME" ]]; then
        echo "No service status directory found"
        return
    fi

    # Check if there is any failure flag file under $SERVICE_DIR/$SCREEN_NAME
    # make this -o errexit safe
    failures=`ls "$SERVICE_DIR/$SCREEN_NAME"/*.failure 2>/dev/null || /bin/true`

    for service in $failures; do
        service=`basename $service`
        service=${service%.failure}
        echo "Error: Service $service is not running"
    done

    if [ -n "$failures" ]; then
        die $LINENO "More details about the above errors can be found with screen"
    fi
}

# Tail a log file in a screen if USE_SCREEN is true.
# Uses globals ``USE_SCREEN``
function tail_log {
    local name=$1
    local logfile=$2

    if [[ "$USE_SCREEN" = "True" ]]; then
        screen_process "$name" "sudo tail -f $logfile | sed -u 's/\\\\\\\\x1b/\o033/g'"
    fi
}


# Deprecated Functions
# --------------------

# _old_run_process() is designed to be backgrounded by old_run_process() to simulate a
# fork.  It includes the dirty work of closing extra filehandles and preparing log
# files to produce the same logs as screen_it().  The log filename is derived
# from the service name and global-and-now-misnamed ``SCREEN_LOGDIR``
# Uses globals ``CURRENT_LOG_TIME``, ``SCREEN_LOGDIR``, ``SCREEN_NAME``, ``SERVICE_DIR``
# _old_run_process service "command-line"
function _old_run_process {
    local service=$1
    local command="$2"

    # Undo logging redirections and close the extra descriptors
    exec 1>&3
    exec 2>&3
    exec 3>&-
    exec 6>&-

    if [[ -n ${SCREEN_LOGDIR} ]]; then
        exec 1>&${SCREEN_LOGDIR}/screen-${1}.log.${CURRENT_LOG_TIME} 2>&1
        ln -sf ${SCREEN_LOGDIR}/screen-${1}.log.${CURRENT_LOG_TIME} ${SCREEN_LOGDIR}/screen-${1}.log

        # TODO(dtroyer): Hack to get stdout from the Python interpreter for the logs.
        export PYTHONUNBUFFERED=1
    fi

    exec /bin/bash -c "$command"
    die "$service exec failure: $command"
}

# old_run_process() launches a child process that closes all file descriptors and
# then exec's the passed in command.  This is meant to duplicate the semantics
# of screen_it() without screen.  PIDs are written to
# ``$SERVICE_DIR/$SCREEN_NAME/$service.pid`` by the spawned child process.
# old_run_process service "command-line"
function old_run_process {
    local service=$1
    local command="$2"

    # Spawn the child process
    _old_run_process "$service" "$command" &
    echo $!
}

# Compatibility for existing start_XXXX() functions
# Uses global ``USE_SCREEN``
# screen_it service "command-line"
function screen_it {
    if is_service_enabled $1; then
        # Append the service to the screen rc file
        screen_rc "$1" "$2"

        if [[ "$USE_SCREEN" = "True" ]]; then
            screen_process "$1" "$2"
        else
            # Spawn directly without screen
            old_run_process "$1" "$2" >$SERVICE_DIR/$SCREEN_NAME/$1.pid
        fi
    fi
}

# Compatibility for existing stop_XXXX() functions
# Stop a service in screen
# If a PID is available use it, kill the whole process group via TERM
# If screen is being used kill the screen window; this will catch processes
# that did not leave a PID behind
# screen_stop service
function screen_stop {
    # Clean up the screen window
    stop_process $1
}


# Plugin Functions
# =================

DEVSTACK_PLUGINS=${DEVSTACK_PLUGINS:-""}

# enable_plugin <name> <url> [branch]
#
# ``name`` is an arbitrary name - (aka: glusterfs, nova-docker, zaqar)
# ``url`` is a git url
# ``branch`` is a gitref. If it's not set, defaults to master
function enable_plugin {
    local name=$1
    local url=$2
    local branch=${3:-master}
    if [[ ",${DEVSTACK_PLUGINS}," =~ ,${name}, ]]; then
        die $LINENO "Plugin attempted to be enabled twice: ${name} ${url} ${branch}"
    fi
    DEVSTACK_PLUGINS+=",$name"
    GITREPO[$name]=$url
    GITDIR[$name]=$DEST/$name
    GITBRANCH[$name]=$branch
}

# fetch_plugins
#
# clones all plugins
function fetch_plugins {
    local plugins="${DEVSTACK_PLUGINS}"
    local plugin

    # short circuit if nothing to do
    if [[ -z $plugins ]]; then
        return
    fi

    echo "Fetching DevStack plugins"
    for plugin in ${plugins//,/ }; do
        git_clone_by_name $plugin
    done
}

# load_plugin_settings
#
# Load settings from plugins in the order that they were registered
function load_plugin_settings {
    local plugins="${DEVSTACK_PLUGINS}"
    local plugin

    # short circuit if nothing to do
    if [[ -z $plugins ]]; then
        return
    fi

    echo "Loading plugin settings"
    for plugin in ${plugins//,/ }; do
        local dir=${GITDIR[$plugin]}
        # source any known settings
        if [[ -f $dir/devstack/settings ]]; then
            source $dir/devstack/settings
        fi
    done
}

# plugin_override_defaults
#
# Run an extremely early setting phase for plugins that allows default
# overriding of services.
function plugin_override_defaults {
    local plugins="${DEVSTACK_PLUGINS}"
    local plugin

    # short circuit if nothing to do
    if [[ -z $plugins ]]; then
        return
    fi

    echo "Overriding Configuration Defaults"
    for plugin in ${plugins//,/ }; do
        local dir=${GITDIR[$plugin]}
        # source any overrides
        if [[ -f $dir/devstack/override-defaults ]]; then
            # be really verbose that an override is happening, as it
            # may not be obvious if things fail later.
            echo "$plugin has overridden the following defaults"
            cat $dir/devstack/override-defaults
            source $dir/devstack/override-defaults
        fi
    done
}

# run_plugins
#
# Run the devstack/plugin.sh in all the plugin directories. These are
# run in registration order.
function run_plugins {
    local mode=$1
    local phase=$2

    local plugins="${DEVSTACK_PLUGINS}"
    local plugin
    for plugin in ${plugins//,/ }; do
        local dir=${GITDIR[$plugin]}
        if [[ -f $dir/devstack/plugin.sh ]]; then
            source $dir/devstack/plugin.sh $mode $phase
        fi
    done
}

function run_phase {
    local mode=$1
    local phase=$2
    if [[ -d $TOP_DIR/extras.d ]]; then
        local extra_plugin_file_name
        for extra_plugin_file_name in $TOP_DIR/extras.d/*.sh; do
            # NOTE(sdague): only process extras.d for the 3 explicitly
            # white listed elements in tree. We want these to move out
            # over time as well, but they are in tree, so we need to
            # manage that.
            local exceptions="80-tempest.sh"
            local extra
            extra=$(basename $extra_plugin_file_name)
            if [[ ! ( $exceptions =~ "$extra" ) ]]; then
                warn "use of extras.d is no longer supported"
                warn "processing of project $extra is skipped"
            else
                [[ -r $extra_plugin_file_name ]] && source $extra_plugin_file_name $mode $phase
            fi
        done
    fi
    # the source phase corresponds to settings loading in plugins
    if [[ "$mode" == "source" ]]; then
        load_plugin_settings
        verify_disabled_services
    elif [[ "$mode" == "override_defaults" ]]; then
        plugin_override_defaults
    else
        run_plugins $mode $phase
    fi
}


# Service Functions
# =================

# remove extra commas from the input string (i.e. ``ENABLED_SERVICES``)
# _cleanup_service_list service-list
function _cleanup_service_list {
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace

    echo "$1" | sed -e '
        s/,,/,/g;
        s/^,//;
        s/,$//
    '

    $xtrace
}

# disable_all_services() removes all current services
# from ``ENABLED_SERVICES`` to reset the configuration
# before a minimal installation
# Uses global ``ENABLED_SERVICES``
# disable_all_services
function disable_all_services {
    ENABLED_SERVICES=""
}

# Remove all services starting with '-'.  For example, to install all default
# services except rabbit (rabbit) set in ``localrc``:
# ENABLED_SERVICES+=",-rabbit"
# Uses global ``ENABLED_SERVICES``
# disable_negated_services
function disable_negated_services {
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace

    local to_remove=""
    local remaining=""
    local service

    # build up list of services that should be removed; i.e. they
    # begin with "-"
    for service in ${ENABLED_SERVICES//,/ }; do
        if [[ ${service} == -* ]]; then
            to_remove+=",${service#-}"
        else
            remaining+=",${service}"
        fi
    done

    # go through the service list.  if this service appears in the "to
    # be removed" list, drop it
    ENABLED_SERVICES=$(remove_disabled_services "$remaining" "$to_remove")

    $xtrace
}

# disable_service() prepares the services passed as argument to be
# removed from the ``ENABLED_SERVICES`` list, if they are present.
#
# For example:
#   disable_service rabbit
#
# Uses global ``DISABLED_SERVICES``
# disable_service service [service ...]
function disable_service {
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace

    local disabled_svcs="${DISABLED_SERVICES}"
    local enabled_svcs=",${ENABLED_SERVICES},"
    local service
    for service in $@; do
        disabled_svcs+=",$service"
        if is_service_enabled $service; then
            enabled_svcs=${enabled_svcs//,$service,/,}
        fi
    done
    DISABLED_SERVICES=$(_cleanup_service_list "$disabled_svcs")
    ENABLED_SERVICES=$(_cleanup_service_list "$enabled_svcs")

    $xtrace
}

# enable_service() adds the services passed as argument to the
# ``ENABLED_SERVICES`` list, if they are not already present.
#
# For example:
#   enable_service q-svc
#
# This function does not know about the special cases
# for nova, glance, and neutron built into is_service_enabled().
# Uses global ``ENABLED_SERVICES``
# enable_service service [service ...]
function enable_service {
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace

    local tmpsvcs="${ENABLED_SERVICES}"
    local service
    for service in $@; do
        if [[ ,${DISABLED_SERVICES}, =~ ,${service}, ]]; then
            warn $LINENO "Attempt to enable_service ${service} when it has been disabled"
            continue
        fi
        if ! is_service_enabled $service; then
            tmpsvcs+=",$service"
        fi
    done
    ENABLED_SERVICES=$(_cleanup_service_list "$tmpsvcs")
    disable_negated_services

    $xtrace
}

# is_service_enabled() checks if the service(s) specified as arguments are
# enabled by the user in ``ENABLED_SERVICES``.
#
# Multiple services specified as arguments are ``OR``'ed together; the test
# is a short-circuit boolean, i.e it returns on the first match.
#
# There are special cases for some 'catch-all' services::
#   **nova** returns true if any service enabled start with **n-**
#   **cinder** returns true if any service enabled start with **c-**
#   **glance** returns true if any service enabled start with **g-**
#   **neutron** returns true if any service enabled start with **q-**
#   **swift** returns true if any service enabled start with **s-**
#   **trove** returns true if any service enabled start with **tr-**
#   For backward compatibility if we have **swift** in ENABLED_SERVICES all the
#   **s-** services will be enabled. This will be deprecated in the future.
#
# Cells within nova is enabled if **n-cell** is in ``ENABLED_SERVICES``.
# We also need to make sure to treat **n-cell-region** and **n-cell-child**
# as enabled in this case.
#
# Uses global ``ENABLED_SERVICES``
# is_service_enabled service [service ...]
function is_service_enabled {
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace

    local enabled=1
    local services=$@
    local service
    for service in ${services}; do
        [[ ,${ENABLED_SERVICES}, =~ ,${service}, ]] && enabled=0

        # Look for top-level 'enabled' function for this service
        if type is_${service}_enabled >/dev/null 2>&1; then
            # A function exists for this service, use it
            is_${service}_enabled && enabled=0
        fi

        # TODO(dtroyer): Remove these legacy special-cases after the is_XXX_enabled()
        #                are implemented

        [[ ${service} == n-cell-* && ,${ENABLED_SERVICES} =~ ,"n-cell" ]] && enabled=0
        [[ ${service} == n-cpu-* && ,${ENABLED_SERVICES} =~ ,"n-cpu" ]] && enabled=0
        [[ ${service} == "nova" && ,${ENABLED_SERVICES} =~ ,"n-" ]] && enabled=0
        [[ ${service} == "glance" && ,${ENABLED_SERVICES} =~ ,"g-" ]] && enabled=0
        [[ ${service} == "neutron" && ,${ENABLED_SERVICES} =~ ,"q-" ]] && enabled=0
        [[ ${service} == "trove" && ,${ENABLED_SERVICES} =~ ,"tr-" ]] && enabled=0
        [[ ${service} == "swift" && ,${ENABLED_SERVICES} =~ ,"s-" ]] && enabled=0
        [[ ${service} == s-* && ,${ENABLED_SERVICES} =~ ,"swift" ]] && enabled=0
    done

    $xtrace
    return $enabled
}

# remove specified list from the input string
# remove_disabled_services service-list remove-list
function remove_disabled_services {
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace

    local service_list=$1
    local remove_list=$2
    local service
    local enabled=""

    for service in ${service_list//,/ }; do
        local remove
        local add=1
        for remove in ${remove_list//,/ }; do
            if [[ ${remove} == ${service} ]]; then
                add=0
                break
            fi
        done
        if [[ $add == 1 ]]; then
            enabled="${enabled},$service"
        fi
    done

    $xtrace

    _cleanup_service_list "$enabled"
}

# Toggle enable/disable_service for services that must run exclusive of each other
#  $1 The name of a variable containing a space-separated list of services
#  $2 The name of a variable in which to store the enabled service's name
#  $3 The name of the service to enable
function use_exclusive_service {
    local options=${!1}
    local selection=$3
    local out=$2
    [ -z $selection ] || [[ ! "$options" =~ "$selection" ]] && return 1
    local opt
    for opt in $options;do
        [[ "$opt" = "$selection" ]] && enable_service $opt || disable_service $opt
    done
    eval "$out=$selection"
    return 0
}

# Make sure that nothing has manipulated ENABLED_SERVICES in a way
# that conflicts with prior calls to disable_service.
# Uses global ``ENABLED_SERVICES``
function verify_disabled_services {
    local service
    for service in ${ENABLED_SERVICES//,/ }; do
        if [[ ,${DISABLED_SERVICES}, =~ ,${service}, ]]; then
            die $LINENO "ENABLED_SERVICES directly modified to overcome 'disable_service ${service}'"
        fi
    done
}


# System Functions
# ================

# Only run the command if the target file (the last arg) is not on an
# NFS filesystem.
function _safe_permission_operation {
    local xtrace
    xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local args=( $@ )
    local last
    local sudo_cmd
    local dir_to_check

    let last="${#args[*]} - 1"

    local dir_to_check=${args[$last]}
    if [ ! -d "$dir_to_check" ]; then
        dir_to_check=`dirname "$dir_to_check"`
    fi

    if is_nfs_directory "$dir_to_check" ; then
        $xtrace
        return 0
    fi

    if [[ $TRACK_DEPENDS = True ]]; then
        sudo_cmd="env"
    else
        sudo_cmd="sudo"
    fi

    $xtrace
    $sudo_cmd $@
}

# Exit 0 if address is in network or 1 if address is not in network
# ip-range is in CIDR notation: 1.2.3.4/20
# address_in_net ip-address ip-range
function address_in_net {
    local ip=$1
    local range=$2
    local masklen=${range#*/}
    local network
    network=$(maskip ${range%/*} $(cidr2netmask $masklen))
    local subnet
    subnet=$(maskip $ip $(cidr2netmask $masklen))
    [[ $network == $subnet ]]
}

# Add a user to a group.
# add_user_to_group user group
function add_user_to_group {
    local user=$1
    local group=$2

    sudo usermod -a -G "$group" "$user"
}

# Convert CIDR notation to a IPv4 netmask
# cidr2netmask cidr-bits
function cidr2netmask {
    local maskpat="255 255 255 255"
    local maskdgt="254 252 248 240 224 192 128"
    set -- ${maskpat:0:$(( ($1 / 8) * 4 ))}${maskdgt:$(( (7 - ($1 % 8)) * 4 )):3}
    echo ${1-0}.${2-0}.${3-0}.${4-0}
}

# Check if this is a valid ipv4 address string
function is_ipv4_address {
    local address=$1
    local regex='([0-9]{1,3}.){3}[0-9]{1,3}'
    # TODO(clarkb) make this more robust
    if [[ "$address" =~ $regex ]] ; then
        return 0
    else
        return 1
    fi
}

# Gracefully cp only if source file/dir exists
# cp_it source destination
function cp_it {
    if [ -e $1 ] || [ -d $1 ]; then
        cp -pRL $1 $2
    fi
}

# HTTP and HTTPS proxy servers are supported via the usual environment variables [1]
# ``http_proxy``, ``https_proxy`` and ``no_proxy``. They can be set in
# ``localrc`` or on the command line if necessary::
#
# [1] http://www.w3.org/Daemon/User/Proxies/ProxyClients.html
#
#     http_proxy=http://proxy.example.com:3128/ no_proxy=repo.example.net ./stack.sh

function export_proxy_variables {
    if isset http_proxy ; then
        export http_proxy=$http_proxy
    fi
    if isset https_proxy ; then
        export https_proxy=$https_proxy
    fi
    if isset no_proxy ; then
        export no_proxy=$no_proxy
    fi
}

# Returns true if the directory is on a filesystem mounted via NFS.
function is_nfs_directory {
    local mount_type
    mount_type=`stat -f -L -c %T $1`
    test "$mount_type" == "nfs"
}

# Return the network portion of the given IP address using netmask
# netmask is in the traditional dotted-quad format
# maskip ip-address netmask
function maskip {
    local ip=$1
    local mask=$2
    local l="${ip%.*}"; local r="${ip#*.}"; local n="${mask%.*}"; local m="${mask#*.}"
    local subnet
    subnet=$((${ip%%.*}&${mask%%.*})).$((${r%%.*}&${m%%.*})).$((${l##*.}&${n##*.})).$((${ip##*.}&${mask##*.}))
    echo $subnet
}

function is_provider_network {
    if [ "$Q_USE_PROVIDER_NETWORKING" == "True" ]; then
        return 0
    fi
    return 1
}


# Return the current python as "python<major>.<minor>"
function python_version {
    local python_version
    python_version=$(python -c 'import sys; print("%s.%s" % sys.version_info[0:2])')
    echo "python${python_version}"
}

# Service wrapper to restart services
# restart_service service-name
function restart_service {
    if [ -x /bin/systemctl ]; then
        sudo /bin/systemctl restart $1
    else
        sudo service $1 restart
    fi

}

# Only change permissions of a file or directory if it is not on an
# NFS filesystem.
function safe_chmod {
    _safe_permission_operation chmod $@
}

# Only change ownership of a file or directory if it is not on an NFS
# filesystem.
function safe_chown {
    _safe_permission_operation chown $@
}

# Service wrapper to start services
# start_service service-name
function start_service {
    if [ -x /bin/systemctl ]; then
        sudo /bin/systemctl start $1
    else
        sudo service $1 start
    fi
}

# Service wrapper to stop services
# stop_service service-name
function stop_service {
    if [ -x /bin/systemctl ]; then
        sudo /bin/systemctl stop $1
    else
        sudo service $1 stop
    fi
}

# Service wrapper to reload services
# If the service was not in running state it will start it
# reload_service service-name
function reload_service {
    if [ -x /bin/systemctl ]; then
        sudo /bin/systemctl reload-or-restart $1
    else
        sudo service $1 reload
    fi
}

# Test with a finite retry loop.
#
function test_with_retry {
    local testcmd=$1
    local failmsg=$2
    local until=${3:-10}
    local sleep=${4:-0.5}

    time_start "test_with_retry"
    if ! timeout $until sh -c "while ! $testcmd; do sleep $sleep; done"; then
        die $LINENO "$failmsg"
    fi
    time_stop "test_with_retry"
}

# Like sudo but forwarding http_proxy https_proxy no_proxy environment vars.
# If it is run as superuser then sudo is replaced by env.
#
function sudo_with_proxies {
    local sudo

    [[ "$(id -u)" = "0" ]] && sudo="env" || sudo="sudo"

    $sudo http_proxy="${http_proxy:-}" https_proxy="${https_proxy:-}"\
        no_proxy="${no_proxy:-}" "$@"
}

# Timing infrastructure - figure out where large blocks of time are
# used in DevStack
#
# The timing infrastructure for DevStack is about collecting buckets
# of time that are spend in some subtask. For instance, that might be
# 'apt', 'pip', 'osc', even database migrations. We do this by a pair
# of functions: time_start / time_stop.
#
# These take a single parameter: $name - which specifies the name of
# the bucket to be accounted against. time_totals function spits out
# the results.
#
# Resolution is only in whole seconds, so should be used for long
# running activities.

declare -A -g _TIME_TOTAL
declare -A -g _TIME_START
declare -r -g _TIME_BEGIN=$(date +%s)

# time_start $name
#
# starts the clock for a timer by name. Errors if that clock is
# already started.
function time_start {
    local name=$1
    local start_time=${_TIME_START[$name]}
    if [[ -n "$start_time" ]]; then
        die $LINENO "Trying to start the clock on $name, but it's already been started"
    fi
    _TIME_START[$name]=$(date +%s)
}

# time_stop $name
#
# stops the clock for a timer by name, and accumulate that time in the
# global counter for that name. Errors if that clock had not
# previously been started.
function time_stop {
    local name
    local end_time
    local elapsed_time
    local total
    local start_time

    name=$1
    start_time=${_TIME_START[$name]}

    if [[ -z "$start_time" ]]; then
        die $LINENO "Trying to stop the clock on $name, but it was never started"
    fi
    end_time=$(date +%s)
    elapsed_time=$(($end_time - $start_time))
    total=${_TIME_TOTAL[$name]:-0}
    # reset the clock so we can start it in the future
    _TIME_START[$name]=""
    _TIME_TOTAL[$name]=$(($total + $elapsed_time))
}

# time_totals
#  Print out total time summary
function time_totals {
    local elapsed_time
    local end_time
    local len=15
    local xtrace

    end_time=$(date +%s)
    elapsed_time=$(($end_time - $_TIME_BEGIN))

    # pad 1st column this far
    for t in ${!_TIME_TOTAL[*]}; do
        if [[ ${#t} -gt $len ]]; then
            len=${#t}
        fi
    done

    xtrace=$(set +o | grep xtrace)
    set +o xtrace

    echo
    echo "========================="
    echo "DevStack Component Timing"
    echo "========================="
    printf "%-${len}s %3d\n" "Total runtime" "$elapsed_time"
    echo
    for t in ${!_TIME_TOTAL[*]}; do
        local v=${_TIME_TOTAL[$t]}
        printf "%-${len}s %3d\n" "$t" "$v"
    done
    echo "========================="

    $xtrace
}

# Restore xtrace
$_XTRACE_FUNCTIONS_COMMON

# Local variables:
# mode: shell-script
# End:
