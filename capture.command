#!/bin/bash
sleep 2
# Captura solo la region de la ventana ConfigTool Granite (x, y, width, height)
screencapture -x -R 870,78,1700,900 "/Volumes/Users-1/rmaglan/Documents/CTool Granite/Granite-Frontend/screenshots/$(date +%Y%m%d_%H%M%S).png"
