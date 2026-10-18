#!/bin/sh
# Os 6 processos que mais usam CPU: "pid %cpu %mem nome"
# Usa duas amostras do top e lê só a segunda, porque a primeira
# mostra a média desde que o processo começou, não o uso atual.
export LC_ALL=C

top -b -n2 -d1 -o %CPU -w 512 2>/dev/null | awk '
  /^top -/ { n++ }
  n == 2 && $1 ~ /^[0-9]+$/ && $12 != "top" {
    name = $12
    for (i = 13; i <= NF; i++) name = name " " $i
    print $1, $9, $10, name
    c++
    if (c >= 6) exit
  }'