@echo off

if NOT "%1" == "x64" if NOT "%1" == "x86" (
    echo Must specify first argument as x86 or x64
    goto :error
)
if "%1" == "x64" (
    set arch=64
    set cmake_gen="Visual Studio 15 2017 Win64"
)
if "%1" == "x86" (
    set arch=32
    set cmake_gen="Visual Studio 15 2017"
)

set boost_dir="C:/local/boost_1_67_0"
set boost_lib_dir="%boost_dir%/lib%arch%-msvc-14.1"
set boost_installer="boost_1_67_0-msvc-14.1-%arch%.exe"
set boost_dl="https://iweb.dl.sourceforge.net/project/boost/boost-binaries/1.67.0/boost_1_67_0-msvc-14.1-%arch%.exe"

cd /D "%~dp0"
set start_dir=%cd%
set source_dir=%start_dir%/solidity

if exist %boost_lib_dir% (
    echo Boost already installed at %boost_lib_dir%, skipping download and install
)
if NOT exist %boost_lib_dir% (
    
    if exist %boost_installer% (
        echo Boost already downloaded: %boost_installer%
    )
    if NOT exist %boost_installer% (
        echo Downloading boost from %boost_dl%
        powershell -Command "Invoke-WebRequest %boost_dl% -OutFile %boost_installer%" || goto :error
    )

    echo Installing boost...
    %boost_installer% /silent || goto :error
)

cd %source_dir%

if exist "build" (
    echo Cleaning build directory
    del /S /Q build\* 1>nul
    >nul 2>nul dir /a-d /s "build\*" && (echo Failed to clean build directory & goto :error)
)
if NOT exist "build" (
    mkdir "build" || goto :error
)

cd "%source_dir%/build" || goto :error

echo Patching libsolc cmake to build shared lib
set solc_cmake=%source_dir%/libsolc/CMakeLists.txt
echo %source_dir%/libsolc/CMakeLists.txt
powershell -Command "(gc %solc_cmake%) -replace 'libsolc libsolc.cpp', 'libsolc SHARED libsolc.cpp' | Out-File %solc_cmake% -encoding ASCII" || goto :error

echo Creating cmake override to force static linking to runtime
set cxx_flag_overrides="%source_dir%/cmake/cxx_flag_overrides.cmake"
echo set(CMAKE_CXX_FLAGS_DEBUG_INIT          "/D_DEBUG /MTd /Zi /Ob0 /Od /RTC1") >> %cxx_flag_overrides%
echo set(CMAKE_CXX_FLAGS_MINSIZEREL_INIT     "/MT /O1 /Ob1 /D NDEBUG")           >> %cxx_flag_overrides%
echo set(CMAKE_CXX_FLAGS_RELEASE_INIT        "/MT /O2 /Ob2 /D NDEBUG")           >> %cxx_flag_overrides%
echo set(CMAKE_CXX_FLAGS_RELWITHDEBINFO_INIT "/MT /Zi /O2 /Ob1 /D NDEBUG")       >> %cxx_flag_overrides%

echo Cmake generation for msvc solidity project
cmake -G %cmake_gen% .. ^
    -DTESTS=Off ^
    -DBOOST_ROOT="%boost_dir%" ^
    -DBoost_USE_STATIC_RUNTIME=ON ^
    -DBoost_USE_MULTITHREADED=OFF ^
    -DBoost_USE_STATIC_LIBS=ON ^
    -DCMAKE_SUPPRESS_REGENERATION=TRUE ^
    -DCMAKE_BUILD_TYPE=RelWithDebInfo ^
    -DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=TRUE ^
    -DCMAKE_USER_MAKE_RULES_OVERRIDE_CXX="%source_dir%/cmake/cxx_flag_overrides.cmake" ^
    || goto :error

echo Preparing jsoncpp source
msbuild jsoncpp-project.vcxproj /p:Configuration=RelWithDebInfo /m:4 /v:minimal

echo Cmake generation for msvc jsoncpp project with static runtime linking
cd "%source_dir%/build/deps/src/jsoncpp-project-build"
del CMakeCache.txt
cmake -G %cmake_gen% "../jsoncpp-project" ^
    -DCMAKE_SUPPRESS_REGENERATION=TRUE ^
    -DCMAKE_USER_MAKE_RULES_OVERRIDE_CXX="%source_dir%/cmake/cxx_flag_overrides.cmake" ^
    || goto :error

echo Building jsoncpp static lib
msbuild "src/lib_json/jsoncpp_lib_static.vcxproj" ^
    /p:Configuration=RelWithDebInfo /m:4 /v:minimal ^
    /p:OutDir="%source_dir%/build/deps/lib/" ^
    /p:AssemblyName="jsoncpp" ^
    /p:TargetName="jsoncpp" ^
    || goto :error


echo Building solidity solution
cd "%source_dir%/build"
msbuild solidity.sln /t:libsolc /p:Configuration=RelWithDebInfo /m:4 /v:minimal || goto :error

echo Copying build files
cd %start_dir%
robocopy "%source_dir%/build/libsolc/RelWithDebInfo" "%start_dir%/build/win-%1" solc.dll
cd %start_dir%


goto :EOF
:error
cd "%start_dir%"
echo Failed
exit /b %errorlevel%