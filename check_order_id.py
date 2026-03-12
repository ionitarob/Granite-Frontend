
import os
import django
import sys

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection

def check_order(idnbr):
    with connection.cursor() as cur:
        cur.execute("SELECT ORDER_NBR FROM dbo.tbl_ConfigOrderHdr WHERE idnbr = %s", (idnbr,))
        row = cur.fetchone()
        if row:
            print(f"IDNBR: {idnbr}, ORDER_NBR: {row[0]}")
        else:
            print(f"No order found for IDNBR {idnbr}")

if __name__ == "__main__":
    check_order(43771)
