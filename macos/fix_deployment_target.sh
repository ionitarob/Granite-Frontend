#!/bin/bash
PROJECT_DIR=$(pwd)
sed -i '' 's/MACOSX_DEPLOYMENT_TARGET = [0-9.]*;/MACOSX_DEPLOYMENT_TARGET = 11.0;/g' Runner.xcodeproj/project.pbxproj
if [ -f "Podfile" ]; then
  sed -i '' "s/platform :osx, '[0-9.]*'/platform :osx, '11.0'/g" Podfile
fi
