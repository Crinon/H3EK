pushd ..\..
call tool windows-font-from-settings maps/fonts/icon_font_settings.txt
call tool font-package font_table_icon

call tool windows-font-from-settings maps/fonts/icon_font_settings_x2.txt
call tool font-package font_table_icon_x2

call tool windows-font-from-settings maps/fonts/icon_font_settings_x3.txt
call tool font-package font_table_icon_x3
pause
popd
