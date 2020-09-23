#!/usr/bin/env python3
import sys, os.path, logging, re, csv, zipfile, io, requests, argparse

NOREBO_ROOT = os.path.dirname(os.path.realpath(__file__))
FILE_LIST = list(csv.DictReader(open(os.path.join(NOREBO_ROOT, 'manifest.csv'))))

def read_file_list(manifest):
    global FILE_LIST
    FILE_LIST = list(csv.DictReader(open(os.path.join(NOREBO_ROOT, manifest))))

def download_files(upstream_dir):
    upstream_dir = os.path.realpath(upstream_dir)
    os.mkdir(upstream_dir)

    with requests.Session() as session:
        session.headers.update({'User-Agent': 'project-norebo/1.0'})
        for fi in FILE_LIST:
            resp = session.get(fi['url'])
            resp.raise_for_status()
            data = resp.content
            if fi['mode'] in ('text', 'source'):
                data = re.sub(b'\r?\n', b'\r', data)
                with open(os.path.join(upstream_dir, fi['filename']), 'wb') as f:
                    f.write(data)
            elif fi['mode'] == 'archive':
                fi['members'] = []
                with zipfile.ZipFile(io.BytesIO(data)) as zf:
                    for member in zf.infolist():
                        fn = os.path.basename(member.filename)
                        if not fn.endswith('.txt'):
                            with open(os.path.join(upstream_dir, fn), 'wb') as f:
                                f.write(zf.read(member))
                            fi['members'].append(fn)


def main():
    logging.basicConfig(format='%(levelname)s: %(message)s', level=logging.INFO)

    parser = argparse.ArgumentParser()
    parser.add_argument(
        '-m', '--manifest', dest='manifest', type=str, default='manifest.csv', help='pass in a different manifest'
    )
    parser.add_argument('DESTINATION')
    args = parser.parse_args()

    if (args.manifest and args.manifest != 'manifest.csv'):
        print(args.manifest)
        read_file_list(args.manifest)

    if os.path.exists(args.DESTINATION):
        logging.error("%s: '%s': Destination already exists", __file__, args.DESTINATION)
        sys.exit(1)

    download_files(args.DESTINATION)

if __name__ == '__main__':
    main()
