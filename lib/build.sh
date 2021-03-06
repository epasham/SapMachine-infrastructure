#!/bin/bash
set -ex

if [[ -z $WORKSPACE ]]; then
  WORKSPACE=$PWD
fi

UNAME=`uname`
if [[ $UNAME == Darwin ]]; then
    SEDFLAGS='-En'
else
    SEDFLAGS='-rn'
fi

if [[ $UNAME == CYGWIN* ]]; then
  WORKSPACE=$(cygpath -u "${WORKSPACE}")
fi

if [[ -z $NO_CHECKOUT ]]; then
  if [ -d SapMachine ]; then
      rm -rf SapMachine;
  fi

  if [[ -z $SAPMACHINE_GIT_REPOSITORY ]]; then
    SAPMACHINE_GIT_REPOSITORY="https://github.com/SAP/SapMachine.git"
  fi

  git clone -b $SAPMACHINE_GIT_BRANCH $SAPMACHINE_GIT_REPOSITORY "${WORKSPACE}/SapMachine"
fi

cd "${WORKSPACE}/SapMachine"

git config user.name SAPMACHINE_GIT_USER
git config user.email SAPMACHINE_GIT_EMAIL

GIT_REVISION=$(git rev-parse HEAD)
echo "Git Revision=${GIT_REVISION}"

GTEST_RESULT_PATH="gtest_all_server"

if [[ -z $NO_CHECKOUT ]]; then
  if [ "$GITHUB_PR_NUMBER" ]; then
    git fetch origin "pull/$GITHUB_PR_NUMBER/head"
    git merge FETCH_HEAD
  fi

  if [[ ! -z $GIT_TAG_NAME ]]; then
    git checkout $GIT_TAG_NAME
  fi
fi

if [ -z $BOOT_JDK ]; then
  # error
  echo "No boot JDK specified!"
  exit 1
fi

VENDOR_NAME="SAP SE"
VENDOR_URL="https://sapmachine.io/"
VENDOR_BUG_URL="https://github.com/SAP/SapMachine/issues/new"
VENDOR_VM_BUG_URL="https://github.com/SAP/SapMachine/issues/new"

if [[ $GIT_TAG_NAME == sapmachine-* ]]; then
  read VERSION VERSION_PART VERSION_MAJOR VERSION_BUILD_NUMBER SAPMACHINE_VERSION VERSION_OS_EXT<<< $(python ${WORKSPACE}/SapMachine-Infrastructure/lib/get_tag_version_components.py -t $GIT_TAG_NAME)

  if [[ -z $VERSION || -z $VERSION_MAJOR ]]; then
    # error
    echo "Invalid tag!"
    exit 1
  fi

  if [[ ! -z $BUILD_NUMBER ]]; then
    _CONFIGURE_OPTION_VERSION_BUILD="--with-version-build=$BUILD_NUMBER"
  elif [[ "$VERSION_BUILD_NUMBER" != "N/A" ]]; then
    _CONFIGURE_OPTION_VERSION_BUILD="--with-version-build=$VERSION_BUILD_NUMBER"
  fi

  if [[ "$SAPMACHINE_VERSION" != "N/A" ]]; then
    _CONFIGURE_OPTION_VERSION_EXTRA="--with-version-extra1=$SAPMACHINE_VERSION"
  fi

  VERSION_PRE_OPT="ea"

  if [ "$RELEASE" == true ]; then
    if [ "$VERSION_MAJOR" == "11" ]; then
      LTS='LTS-'
    else
      LTS=''
    fi

    VERSION_PRE_OPT=''
  fi

  VERSION_DATE=$(python ../SapMachine-Infrastructure/lib/get_tag_timestamp.py -t $GIT_TAG_NAME)

  if [[ -z $VERSION_DATE ]]; then
    VERSION_DATE=$(date -u "+%Y-%m-%d")
  fi

  bash ./configure \
  --with-boot-jdk=$BOOT_JDK \
  --with-version-feature=$VERSION_MAJOR \
  --with-version-opt=${LTS}sapmachine \
  --with-version-pre=$VERSION_PRE_OPT \
  --with-version-date=$VERSION_DATE \
  --disable-warnings-as-errors \
  --with-vendor-name="$VENDOR_NAME" \
  --with-vendor-url="$VENDOR_URL" \
  --with-vendor-bug-url="$VENDOR_BUG_URL" \
  --with-vendor-vm-bug-url="$VENDOR_VM_BUG_URL" \
    $_CONFIGURE_OPTION_VERSION_BUILD \
    $_CONFIGURE_OPTION_VERSION_EXTRA \
    $_CONFIGURE_SYSROOT \
    $EXTRA_CONFIGURE_OPTIONS
else
  if [[ ! -z $BUILD_NUMBER ]]; then
    _CONFIGURE_OPTION_VERSION_BUILD="--with-version-build=$BUILD_NUMBER"
  fi

  BUILD_DATE=$(date -u "+%Y-%m-%d")
  bash ./configure \
  --with-boot-jdk=$BOOT_JDK \
  --with-version-opt="sapmachine-$BUILD_DATE" \
  --with-version-pre=snapshot \
  --disable-warnings-as-errors \
  --with-vendor-name="$VENDOR_NAME" \
  --with-vendor-url="$VENDOR_URL" \
  --with-vendor-bug-url="$VENDOR_BUG_URL" \
  --with-vendor-vm-bug-url="$VENDOR_VM_BUG_URL" \
    $_CONFIGURE_OPTION_VERSION_BUILD \
    $_CONFIGURE_SYSROOT \
    $EXTRA_CONFIGURE_OPTIONS
fi

make JOBS=12 product-bundles test-image

legacy_bundles_available=1
make JOBS=12 legacy-bundles | true

if [ ${PIPESTATUS[0]} -ne 0 ]; then
  legacy_bundles_available=0
fi

if [ $legacy_bundles_available -ne 1 ]; then
  if [[ $UNAME == Darwin ]]; then
    make JOBS=12 mac-legacy-jre-bundle || true
  else
      make JOBS=12 legacy-jre-image || true
  fi
fi

make run-test-gtest

rm "${WORKSPACE}/test.zip" || true
zip -rq "${WORKSPACE}/test.zip" test
zip -rq "${WORKSPACE}/test.zip" make/data/lsrdata
zip -rq "${WORKSPACE}/test.zip" make/data/blacklistedcertsconverter/blacklisted.certs.pem || true

cd "${WORKSPACE}/SapMachine/build"
cd "$(ls)"
zip -rq ${WORKSPACE}/support_gensrc.zip support/gensrc
zip -rq ${WORKSPACE}/test.zip spec.gmk
zip -rq ${WORKSPACE}/test.zip bundles/*jdk-*_bin.*
cd images
zip -rq ${WORKSPACE}/test.zip test

cd ../bundles

if [ "$(ls sapmachine-jdk-*_bin.* | wc -l)" -gt "0" ]; then
  SAPMACHINE_BUNDLE_PREFIX="sapmachine-"
fi

JDK_NAME=$(ls ${SAPMACHINE_BUNDLE_PREFIX}jdk-*_bin.*)
read JDK_MAJOR JDK_SUFFIX<<< $(echo $JDK_NAME | sed $SEDFLAGS 's/'"${SAPMACHINE_BUNDLE_PREFIX}"'jdk-([0-9]+((\.[0-9]+))*)(.*)/ \1 \4 /p')
JDK_BUNDLE_NAME="${SAPMACHINE_BUNDLE_PREFIX}jdk-${JDK_MAJOR}${JDK_SUFFIX}"
JRE_BUNDLE_NAME="${SAPMACHINE_BUNDLE_PREFIX}jre-${JDK_MAJOR}${JDK_SUFFIX}"

if [ $legacy_bundles_available -ne 1 ]; then
  HAS_JRE=$(ls ${SAPMACHINE_BUNDLE_PREFIX}jre* | wc -l)

  if [ "$HAS_JRE" -lt "1" ]; then
    JRE_BUNDLE_TOP_DIR="${SAPMACHINE_BUNDLE_PREFIX}jre-$JDK_MAJOR.jre"

    rm -rf $JRE_BUNDLE_NAME
    mkdir $JRE_BUNDLE_TOP_DIR
    if [[ $UNAME == Darwin ]]; then
        cp -a ../images/${SAPMACHINE_BUNDLE_PREFIX}jre-bundle/$JRE_BUNDLE_TOP_DIR* .
        SetFile -a b ${SAPMACHINE_BUNDLE_PREFIX}jre*
    else
        cp -r ../images/jre/* $JRE_BUNDLE_TOP_DIR
    fi
    find $JRE_BUNDLE_TOP_DIR -name "*.debuginfo" -type f -delete

    if [ ${JDK_SUFFIX: -4} == ".zip" ]; then
      zip -r $JRE_BUNDLE_NAME $JRE_BUNDLE_TOP_DIR
    else
      tar -czf  $JRE_BUNDLE_NAME $JRE_BUNDLE_TOP_DIR
    fi

    rm -rf $JRE_BUNDLE_TOP_DIR
  fi
fi

rm "${WORKSPACE}/${SAPMACHINE_BUNDLE_PREFIX}jdk-*" || true
rm "${WORKSPACE}/${SAPMACHINE_BUNDLE_PREFIX}jre-*" || true

cp ${JDK_BUNDLE_NAME} "${WORKSPACE}"
cp ${JRE_BUNDLE_NAME} "${WORKSPACE}"

if [ "$RELEASE" == true ]; then
  # remove build number +xx from release build filenames
  ARCHIVE_NAME_JDK="$(echo $JDK_BUNDLE_NAME | sed 's/\+[0-9]*//')"
  ARCHIVE_NAME_JRE="$(echo $JRE_BUNDLE_NAME | sed 's/\+[0-9]*//')"
else
  # substitute build number +xx to .xx to avoid problmes with uploads. + is no good character :-)
  ARCHIVE_NAME_JDK="$(echo $JDK_BUNDLE_NAME | sed 's/\+/\./')"
  ARCHIVE_NAME_JRE="$(echo $JRE_BUNDLE_NAME | sed 's/\+/\./')"
fi

mv "${WORKSPACE}/${JDK_BUNDLE_NAME}" "${WORKSPACE}/${ARCHIVE_NAME_JDK}"
mv "${WORKSPACE}/${JRE_BUNDLE_NAME}" "${WORKSPACE}/${ARCHIVE_NAME_JRE}"

echo "${ARCHIVE_NAME_JDK}" > "${WORKSPACE}/jdk_bundle_name.txt"
echo "${ARCHIVE_NAME_JRE}" > "${WORKSPACE}/jre_bundle_name.txt"

cp ../test-results/$GTEST_RESULT_PATH/gtest.xml "${WORKSPACE}"
