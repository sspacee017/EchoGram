import json
import os
from pathlib import Path
import re
import sys

file_name, output = sys.argv[1:]

try:
    if file_name:
        with Path(file_name).open("rb") as stream:
            data = stream.read(4097)
        if len(data) > 4096:
            raise ValueError
        credentials = json.loads(data)
        api_id = credentials["api_id"]
        api_hash = credentials["api_hash"]
    else:
        api_id = int(os.environ["ECHOGRAM_TELEGRAM_API_ID"])
        api_hash = os.environ["ECHOGRAM_TELEGRAM_API_HASH"]
    if type(api_id) is not int or not 0 < api_id < 2**31:
        raise ValueError
    if not isinstance(api_hash, str) or not re.fullmatch("[a-fA-F0-9]{32}", api_hash):
        raise ValueError
except (OSError, ValueError, KeyError, TypeError):
    sys.exit("Invalid Telegram API credentials")

os.umask(0o077)
with Path(output).open("x") as header:
    header.write(f'#define ECHOGRAM_API_ID {api_id}\n#define ECHOGRAM_API_HASH "{api_hash}"\n')
