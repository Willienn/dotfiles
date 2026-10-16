#!/bin/sh
# Coleta atualizações pendentes: repo oficial, AUR e Flatpak.
# Uma linha por item, prefixada: "repo ...", "aur ...", "flatpak ..."
# Se o banco do pacman estiver ocupado, imprime só "locked".
export LC_ALL=C

# Banco do pacman ocupado? (outro pacman/yay rodando)
if [ -e /var/lib/pacman/db.lck ]; then
    echo "locked"
    exit 0
fi

# Repo oficial (checkupdates sai com código 2 quando não há nada; não é erro)
checkupdates 2>/dev/null | while IFS= read -r line; do
    echo "repo $line"
done

# AUR
yay -Qua 2>/dev/null | while IFS= read -r line; do
    echo "aur $line"
done

# Flatpak (remote-ls --updates lista só o que tem update)
# Formato: id<TAB>branch<TAB>remote<TAB>version<TAB>u
flatpak remote-ls --updates 2>/dev/null | while IFS="$(printf '\t')" read -r id branch remote version flag; do
    [ -n "$id" ] && echo "flatpak $id $version"
done