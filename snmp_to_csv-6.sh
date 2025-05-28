#!/bin/bash

# ======================================
# 📦 Script d’inventaire SNMP → CSV NetBox
# ======================================

# --- Configuration de base ---
TARGET="10.76.116.107"         # Adresse IP du switch cible
COMMUNITY="public"             # Communauté SNMP v2c
CSV_FILE="netbox_inventory.csv"

# --- Vérification de dépendances ---
if ! command -v xxd &> /dev/null; then
    echo "❌ Erreur : 'xxd' est requis. Installez-le avec : sudo apt install xxd"
    exit 1
fi

# --- Titre ---
echo "======================================"
echo "[+] Interrogation SNMP de $TARGET"
echo "======================================"

# --- Récupération des infos générales ---
HOSTNAME=$(snmpget -v2c -c $COMMUNITY -Oqv -m "" $TARGET .1.3.6.1.2.1.1.5.0 | tr -d '"' | tr -d '\r\n')
FIRMWARE=$(snmpget -v2c -c $COMMUNITY -Oqv -m "" $TARGET .1.3.6.1.2.1.1.1.0 | tr '\n' ' ' | tr -d '"' | sed 's/,/ /g')
IPADDR=$(snmpwalk -v2c -c $COMMUNITY -Oqv -m "" $TARGET .1.3.6.1.2.1.4.20.1.1 | head -n 1)
MACADDR=$(snmpget -v2c -c $COMMUNITY -Oqv -m "" $TARGET .1.3.6.1.2.1.2.2.1.6.1 | sed 's/ /:/g')

# --- Récupération de la liste des interfaces ---
INTERFACES=$(snmpwalk -v2c -c $COMMUNITY -Oqv -m "" $TARGET .1.3.6.1.2.1.2.2.1.2)
INDEX=1

# --- IP par interface (via ifIndex) ---
declare -A IP_BY_IFINDEX
while read -r ip; do
    ifindex=$(snmpget -v2c -c $COMMUNITY -Oqv -m "" $TARGET .1.3.6.1.2.1.4.20.1.2.$ip)
    IP_BY_IFINDEX["$ifindex"]=$ip
done < <(snmpwalk -v2c -c $COMMUNITY -Oqv -m "" $TARGET .1.3.6.1.2.1.4.20.1.1)

# --- VLAN untagged (PVID par port) ---
declare -A VLAN_UNTAGGED
while read -r line; do
    port_id=$(echo "$line" | cut -d '.' -f13)
    vlan_id=$(echo "$line" | awk '{print $NF}')
    VLAN_UNTAGGED["$port_id"]=$vlan_id
done < <(snmpwalk -v2c -c $COMMUNITY -On -m "" $TARGET .1.3.6.1.2.1.17.7.1.4.5.1.1)

# --- VLAN taggés (bitmap egress) ---
declare -A VLAN_TAGGED
while read -r line; do
    oid=$(echo "$line" | cut -d ' ' -f1)
    vlan_id=$(echo "$oid" | awk -F '.' '{print $NF}')
    hex_ports=$(echo "$line" | awk -F 'Hex-STRING: ' '{print $2}' | xxd -r -p | od -An -t u1)

    i=1
    for port in $hex_ports; do
        if [[ "$port" -ne 0 ]]; then
            VLAN_TAGGED["$i"]+="$vlan_id,"
        fi
        ((i++))
    done
done < <(snmpwalk -v2c -c $COMMUNITY -On -m "" $TARGET .1.3.6.1.2.1.17.7.1.4.3.1.2)

# --- En-tête CSV ---
echo "hostname,ip_address,mac_address,firmware_version,interface,interface_ip,vlan_untagged,vlan_tagged" > $CSV_FILE

# --- Traitement de chaque interface ---
while read -r iface; do
    iface_clean=$(echo "$iface" | sed 's/STRING: //' | tr -d '"')

    # ❌ Ignore les interfaces non physiques
    if [[ ! "$iface_clean" =~ ^(GigabitEthernet|TenGigabitEthernet|FortyGigE) ]]; then
        ((INDEX++))
        continue
    fi

    iface_ip="${IP_BY_IFINDEX[$INDEX]}"
    untagged="${VLAN_UNTAGGED[$INDEX]}"
    tagged="${VLAN_TAGGED[$INDEX]}"

    # ✅ Génération de la ligne CSV
    echo "\"$HOSTNAME\",\"$IPADDR\",\"$MACADDR\",\"$FIRMWARE\",\"$iface_clean\",\"$iface_ip\",\"$untagged\",\"$tagged\"" >> $CSV_FILE

    ((INDEX++))
done <<< "$INTERFACES"

# --- Fin ---
echo "======================================"
echo "[✔] Fichier CSV enrichi généré : $CSV_FILE"
echo "======================================"

