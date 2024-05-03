pushd ..\..
call tool upgrade-font-package font_package_kor
call tool upgrade-font-package font_package_jpn
call tool upgrade-font-package font_package_cht
popd

rename font_package_kor.bin font_package_kor_old.bin
rename font_package_jpn.bin font_package_jpn_old.bin
rename font_package_cht.bin font_package_cht_old.bin

rename font_package_kor_upgraded.bin font_package_kor.bin
rename font_package_jpn_upgraded.bin font_package_jpn.bin
rename font_package_cht_upgraded.bin font_package_cht.bin


