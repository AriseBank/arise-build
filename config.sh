#!/bin/bash
# shellcheck disable=SC2034
# Override "unused" variables. This file is used to populate build.sh.
# shellcheck disable=SC2155
# Override declare and assign variables seperately. We dont care about return values for path exports.

if [ ! -z "$1" ]; then
  echo "Overriding architecture with: $1"
  echo "--------------------------------------------------------------------------"
  ARCH="$1"
fi

VERSION="BUILD_VERSION"
OS=$(uname)
[ ! -z "$ARCH" ] || ARCH=$(uname -m)
BUILD_NAME="arise-$VERSION-$OS-$ARCH"
NOVER_BUILD_NAME="arise-$OS-$ARCH"
TARGET=""
JOBS="2"

ARISE_DIR="$VERSION"
ARISE_FILE="$VERSION.tar.gz"
ARISE_NETWORK="BUILD_NETWORK"
ARISE_URL="https://downloads.arise.io/arise/$ARISE_NETWORK/$VERSION/$ARISE_FILE"
ARISE_CONFIG=""

ARISE_NODE_DIR="arise-node-6.11.1-arise"
ARISE_NODE_FILE="$ARISE_NODE_DIR.tar.gz"
ARISE_NODE_URL="https://github.com/arisebank/arise-node/archive/v6.11.1-arise.tar.gz"
ARISE_NODE_OUT="out/Release/node"
ARISE_NODE_CONFIG=""

NODE_DIR="node-v6.11.1"
NODE_FILE="$NODE_DIR.tar.gz"
NODE_URL="https://nodejs.org/download/release/v6.11.1/$NODE_FILE"
NODE_OUT="compiled"
NODE_CONFIG=""

POSTGRESQL_DIR="postgresql-9.6.3"
POSTGRESQL_FILE="$POSTGRESQL_DIR.tar.gz"
POSTGRESQL_URL="https://ftp.postgresql.org/pub/source/v9.6.3/$POSTGRESQL_FILE"
POSTGRESQL_OUT="pgsql"

SODIUM_DIR="libsodium-1.0.11"
SODIUM_FILE="$SODIUM_DIR.tar.gz"
SODIUM_URL="https://download.libsodium.org/libsodium/releases/$SODIUM_FILE"
SODIUM_OUT="compiled"

NODE_SODIUM_DIR="node-sodium-master"
NODE_SODIUM_FILE="$NODE_SODIUM_DIR.tar.gz"
NODE_SODIUM_URL="https://github.com/arisebank/node-sodium/archive/master.tar.gz"

REDIS_SERVER_DIR="redis-3.2.9"
REDIS_SERVER_FILE="$REDIS_SERVER_DIR.tar.gz"
REDIS_SERVER_URL="http://download.redis.io/releases/$REDIS_SERVER_FILE"
REDIS_SERVER_OUT="redis-server"
REDIS_SERVER_CLI="redis-cli"
REDIS_SERVER_CONFIG=""

LIBREADLINE_DIR="readline-master"
LIBREADLINE_FILE="$LIBREADLINE_DIR.tar.gz"
LIBREADLINE_URL="http://git.savannah.gnu.org/cgit/readline.git/snapshot/$LIBREADLINE_FILE"
LIBREADLINE_OUT="libreadline.so.7.0"
LIBREADLINE_HISTORY="libhistory.so.7.3"

NPM_CLI="$BUILD_NAME/lib/node_modules/npm/bin/npm-cli.js"

if [ "$(uname -s)" == "Darwin" ]; then
  SED_OPTS="-i ''"
else
  SED_OPTS="-i"
fi

if [ "$(uname -s)" == "Darwin" ]; then
  SHA_CMD="shasum -a 256"
else
  SHA_CMD="sha256sum"
fi

# Needed to build Redis as 32bit
if [ "$(uname -m)" == "i686" ]; then
  REDIS_SERVER_CONFIG="32bit"
fi

if [ "$TARGET" != "" ]; then
  export CC="${TARGET}-gcc"
  export CXX="${TARGET}-g++"
  export AR="${TARGET}-ar"
  export RANLIB="${TARGET}-ranlib"
  export LD="${TARGET}-ld"
  export CPP="${TARGET}-gcc -E"
  export STRIP="${TARGET}-strip"
  export OBJCOPY="${TARGET}-objcopy"
  export OBJDUMP="${TARGET}-objdump"
  export NM="${TARGET}-nm"
  export AS="${TARGET}-as"
fi
