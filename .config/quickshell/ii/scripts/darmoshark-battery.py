#!/usr/bin/env python3
"""
darmoshark-battery — lê o report 0x54 do dongle Darmoshark/Attack Shark M3
(248A:FF30 no dongle, 248A:FF12 no cabo) e emite uma linha JSON por evento.

Não escreve nada no dispositivo. Só escuta.

Validado contra o UPower via Bluetooth: o byte 4 do payload é a
porcentagem da bateria. O byte 5 fica fixo em 0x03 e provavelmente
é tensão ou escala — não usado aqui.

Uso:
    ./darmoshark-battery.py            # JSON por linha
    ./darmoshark-battery.py --debug    # inclui bytes crus e não deduplica
"""

import glob
import json
import os
import sys
import time

VENDOR = "248A"
USAGE_PAGE_SIG = "058c"   # Usage Page 0x8C — interface de configuração
REPORT_ID = 0x54
READ_SIZE = 64

STATE_DIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
STATE_FILE = os.path.join(STATE_DIR, "darmoshark-battery.json")

DEBUG = "--debug" in sys.argv


def find_device():
    """Acha o hidraw da interface de config pelo vendor + usage page.

    Não confia no número do nó: hidraw1 hoje pode ser hidraw4 amanhã.
    Funciona igual no dongle e no cabo — os descritores são idênticos.
    """
    for node in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            with open(f"{node}/device/uevent") as f:
                if VENDOR not in f.read().upper():
                    continue
            with open(f"{node}/device/report_descriptor", "rb") as f:
                if USAGE_PAGE_SIG in f.read().hex():
                    return "/dev/" + os.path.basename(node)
        except OSError:
            continue
    return None


def parse(buf):
    """Decodifica o payload do report 0x54.

    Formato observado (20 bytes, depois do report id):
        e2 01 01 00 1b 03 00 00 ...
        │  │  │  │  │  │
        │  │  │  │  │  └── fixo em 0x03
        │  │  │  │  └───── bateria em % (0x1b = 27)
        │  │  │  └──────── flag que oscila 0/1
        │  │  └─────────── estado que oscila 0/1/2
        └──┴────────────── cabeçalho fixo do evento
    """
    p = buf[1:]
    if len(p) < 6:
        return None

    # O dongle manda um report todo zerado como fim de transmissão.
    # Não é leitura válida — ignorar, senão o widget pisca pra 0%.
    if not any(p[:6]):
        return None

    data = {
        "percentage": p[4],
        "state": p[2],
        "flag": p[3],
        "ts": int(time.time()),
    }
    if DEBUG:
        data["raw"] = p.hex(" ")
    return data


def save_state(data):
    """Grava atômico pra barra ter valor no boot, antes do primeiro evento."""
    tmp = STATE_FILE + ".tmp"
    try:
        with open(tmp, "w") as f:
            json.dump(data, f)
        os.replace(tmp, STATE_FILE)
    except OSError:
        pass


def emit(data):
    print(json.dumps(data), flush=True)
    save_state(data)


def load_cached():
    """Reemite o último valor conhecido, se for válido."""
    try:
        with open(STATE_FILE) as f:
            cached = json.load(f)
    except (OSError, ValueError):
        return
    if cached.get("percentage", 0) > 0:
        cached["cached"] = True
        print(json.dumps(cached), flush=True)


def main():
    load_cached()
    last = None

    while True:
        path = find_device()
        if not path:
            print(json.dumps({"error": "dongle ausente"}), flush=True)
            time.sleep(5)
            continue

        try:
            with open(path, "rb", buffering=0) as dev:
                print(json.dumps({"connected": path}), flush=True)
                while True:
                    buf = dev.read(READ_SIZE)
                    if not buf or buf[0] != REPORT_ID:
                        continue
                    data = parse(buf)
                    if not data:
                        continue
                    key = (data["percentage"], data["state"], data["flag"])
                    if key != last or DEBUG:
                        last = key
                        emit(data)
        except PermissionError:
            print(json.dumps({"error": f"sem permissão em {path}"}), flush=True)
            time.sleep(10)
        except OSError:
            # Dongle desconectado — volta pro scan.
            time.sleep(2)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
