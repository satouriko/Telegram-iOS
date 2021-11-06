import os
import json

g = os.walk('build/artifacts')
media = []
files = []
for path, dir_list, file_list in g:
    for file_name in file_list:
        media.append({
            'type': 'document',
            'media': 'attach://' + file_name,
        })
        files.append((file_name, os.path.join(path, file_name)))
curl = 'curl {}/bot{}/sendMediaGroup -X POST'.format(os.environ['BOT_API_SERVER'], os.environ['BOT_TOKEN'])
curl += ' -F chat_id="{}"'.format(os.environ['CHANNEL_ID'])
curl += ' -F media=\'' + json.dumps(media, separators=(',', ':')) + '\''
for file_name, file_path in files:
    curl += ' -F ' + file_name + '=\'@' + file_path + '\''
print(curl)
