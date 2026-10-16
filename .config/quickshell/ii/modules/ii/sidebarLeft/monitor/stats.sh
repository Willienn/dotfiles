#!/bin/sh
# Coleta métricas do sistema, uma linha por métrica: "chave valores..."
export LC_ALL=C

# CPU: contadores acumulados (o uso é calculado pelo QML a partir da diferença)
head -n1 /proc/stat | awk '{print "cpu", $2, $3, $4, $5, $6, $7, $8, $9}'

# Memória e swap (kB)
awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} /^SwapTotal/{st=$2} /^SwapFree/{sf=$2} END{print "mem", t, a, st, sf}' /proc/meminfo

# Temperatura da CPU (zenpower3 / k10temp / coretemp), em milésimos de grau
for h in /sys/class/hwmon/hwmon*; do
  name=$(cat "$h/name" 2>/dev/null)
  case "$name" in
    zenpower|k10temp|coretemp)
      t=$(cat "$h/temp1_input" 2>/dev/null)
      if [ -n "$t" ]; then
        echo "cputemp $t"
        break
      fi
      ;;
  esac
done

# GPU: escolhe a placa com mais VRAM (ignora a iGPU quando existe uma dedicada)
best=""
bestv=0
for d in /sys/class/drm/card[0-9]*/device; do
  [ -r "$d/mem_info_vram_total" ] || continue
  v=$(cat "$d/mem_info_vram_total" 2>/dev/null)
  [ -n "$v" ] || continue
  if [ "$v" -gt "$bestv" ]; then
    bestv=$v
    best=$d
  fi
done

if [ -n "$best" ]; then
  busy=$(cat "$best/gpu_busy_percent" 2>/dev/null || echo -1)
  used=$(cat "$best/mem_info_vram_used" 2>/dev/null || echo 0)
  echo "gpu $busy $used $bestv"
  for h in "$best"/hwmon/hwmon*; do
    [ -d "$h" ] || continue
    t=$(cat "$h/temp1_input" 2>/dev/null)
    [ -n "$t" ] && echo "gputemp $t"
    p=$(cat "$h/power1_average" 2>/dev/null || cat "$h/power1_input" 2>/dev/null)
    [ -n "$p" ] && echo "gpupower $p"
    break
  done
fi

# Disco (raiz), em bytes
df -B1 --output=used,size / 2>/dev/null | tail -n1 | awk '{print "disk", $1, $2}'
