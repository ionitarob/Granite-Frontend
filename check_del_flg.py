
import os
import django
import sys

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection

def check_del_flg(idnbr, sku):
    with connection.cursor() as cur:
        cur.execute("SELECT SKU, IMS_DEL_FLG FROM dbo.tbl_ConfigOrderLine WHERE parent_idnbr = %s AND SKU = %s", (idnbr, sku))
        row = cur.fetchone()
        if row:
            print(f"SKU: {row[0]}, IMS_DEL_FLG: {row[1]}")
        else:
            print(f"No line found for SKU {sku} in order {idnbr}")

if __name__ == "__main__":
    check_del_flg(43771, 'CE06603')
