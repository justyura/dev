#!/bin/bash

# 更新 SketchyBar 时钟条目的时间；星期和日期交给系统菜单栏。

sketchybar --set calendar label="$(TZ='Etc/GMT-8' date '+%H:%M')"
