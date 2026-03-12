
import os
import django
import sys
from django.core.management import call_command

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

try:
    print("Running makemigrations...")
    call_command('makemigrations', 'orderops')
    print("Running migrate...")
    call_command('migrate', 'orderops')
    print("Success!")
except Exception as e:
    print(f"Error: {e}")
