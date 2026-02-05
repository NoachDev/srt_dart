# Create SRT library

BUILD_DIR=$(pwd)/native/srt/_build

mkdir -p $BUILD_DIR
cd $BUILD_DIR
cmake .. -DENABLE_UNITTESTS=ON

cmake --build ./


