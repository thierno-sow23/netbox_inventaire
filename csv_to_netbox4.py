import csv
import pynetbox
import requests
import urllib3

# --- Configuration ---
NETBOX_URL = "https://XX.XX.XX.XX" # Mettre l'adresse IP du switch concerné
NETBOX_TOKEN = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" # Mettre le Token généré à partir de l'interface de NetBox
CSV_FILE = "netbox_inventory.csv"

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
session = requests.Session()
session.verify = False

nb = pynetbox.api(NETBOX_URL, token=NETBOX_TOKEN)
nb.http_session = session

# === Récupération des objets liés globaux ===
site = nb.dcim.sites.get(name="Rouen")
role = nb.dcim.device_roles.get(name="switch")
dtype = nb.dcim.device_types.get(model="HPE 5140 48G PoE+ 4SFP+ EI JG937A")

if not site or not role or not dtype:
    print("❌ Site, rôle ou type d'équipement introuvable dans NetBox.")
    exit(1)
else:
    print("✅ Objets liés récupérés :")
    print(f"   ↪️ site.id = {site.id}")
    print(f"   ↪️ role.id = {role.id}")
    print(f"   ↪️ device_type.id = {dtype.id}")

# === Lecture du fichier CSV ===
with open(CSV_FILE, newline='') as csvfile:
    reader = csv.DictReader(csvfile)
    for row in reader:
        hostname = row["hostname"]
        ip_addr = row["ip_address"]
        iface_name = row["interface"].replace("STRING: ", "").strip('"').strip()

        print(f"\n[→] Traitement de {hostname} | Interface : {iface_name} | IP : {ip_addr}")

        # === Création ou récupération du device ===
        device = nb.dcim.devices.get(name=hostname)
        if not device:
            print("  [📦] Appareil non trouvé. Création en cours...")
            print(f"  ↪️ debug : device_type.id = {dtype.id}, device_role.id = {role.id}, site.id = {site.id}")

            device = nb.dcim.devices.create({
                "name": hostname,
                "device_type": dtype.id,
                "role": role.id,
                "site": site.id,
                "status": "active",
            })
            print(f"  ✅ Appareil créé avec ID : {device.id}")
        else:
            print(f"  [✓] Appareil déjà existant : ID = {device.id}")

        # === Création ou vérification de l'interface ===
        interface = nb.dcim.interfaces.get(device=hostname, name=iface_name)
        if not interface:
            interface = nb.dcim.interfaces.create({
                "device": device.id,
                "name": iface_name,
                "type": "1000base-t",
            })
            print(f"  [+] Interface créée : {iface_name} (ID: {interface.id})")
        else:
            print(f"  [✓] Interface existante : {iface_name} (ID: {interface.id})")

        # === Création ou vérification de l'IP ===
        full_ip = f"{ip_addr}/24"
        ip = nb.ipam.ip_addresses.get(address=full_ip)
        if not ip:
            ip = nb.ipam.ip_addresses.create({
                "address": full_ip,
                "status": "active",
            })
            print(f"  [+] IP ajoutée : {full_ip} (ID: {ip.id})")
        else:
            print(f"  [✓] IP déjà présente : {full_ip} (ID: {ip.id})")

print("\n[✔] Importation dans NetBox terminée.")

