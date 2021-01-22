#!/usr/bin/env python3
import sys, os, os.path, argparse, logging, csv, subprocess

NOREBO_ROOT = os.path.dirname(os.path.realpath(__file__))
FILE_LIST = list(csv.DictReader(open(os.path.join(NOREBO_ROOT, 'manifests/manifest.csv'))))
top = ""
exclude_source = False

def read_file_list(manifest):
    global FILE_LIST
    FILE_LIST = list(csv.DictReader(open(os.path.join(NOREBO_ROOT, manifest))))

def bulk_delete(dir, ext):
    for fn in os.listdir(dir):
        parts = fn.split('.')
        if parts[-1] == ext:
            os.remove(os.path.join(dir, fn))

def bulk_rename(dir, old_ext, new_ext):
    for fn in os.listdir(dir):
        parts = fn.split('.')
        if parts[-1] == old_ext:
            parts[-1] = new_ext
            os.rename(os.path.join(dir, fn),
                      os.path.join(dir, '.'.join(parts)))

def mksubdir(parent, subdir):
    fn = os.path.join(parent, subdir)
    os.mkdir(fn)
    return fn


def norebo(args, working_directory='.', search_path=()):
    norebo = os.path.join(NOREBO_ROOT, 'norebo')
    norebo_path = os.pathsep.join(search_path)
    os.environ['NOREBO_PATH'] = norebo_path
    logging.debug('Running norebo\n\tCWD = %s\n\tPATH = %s\n\t%s',
                  working_directory, norebo_path, ' '.join(args))
    output = subprocess.check_output([norebo] + list(args), cwd=working_directory).decode("utf-8")
    print(output)
    if "FAILED" in output:
        raise Exception("Compilation failed.")

def compile(modules, **kwargs):
    norebo(['ORP.Compile'] + [m+'/s' for m in modules], **kwargs)

def rv_compile(modules, **kwargs):
    norebo(['RVOP.Compile'] + [m+'/s' for m in modules], **kwargs)

def rv_build_norebo(target_dir):
    compile(['Norebo.Mod', 'Kernel.Mod', 'FileDir.Mod', 'Files.Mod',
             'Modules.Mod', 'Fonts.Mod', 'Texts.Mod', 'RS232.Mod', 'Oberon.Mod',
             'ORS.Mod', 'ORB.Mod', 'ORG.Mod', 'ORP.Mod', 'RVCoreLinker.Mod',
             'VDisk.Mod', 'VFileDir.Mod', 'VFiles.Mod', 'VDiskUtil.Mod'],
            working_directory=target_dir,
            search_path=[os.path.join(NOREBO_ROOT, 'Norebo'),
                         os.path.join(NOREBO_ROOT, 'Oberon'),
                         os.path.join(NOREBO_ROOT, 'Bootstrap')])

    bulk_rename(target_dir, 'rsc', 'rsx')
    norebo(['CoreLinker.LinkSerial', 'Modules', 'InnerCore'],
           working_directory=target_dir,
           search_path=[os.path.join(NOREBO_ROOT, 'Norebo'),
                        os.path.join(NOREBO_ROOT, 'Bootstrap')])
    bulk_rename(target_dir, 'rsx', 'rsc')

def build_norebo(target_dir):
    compile(['Norebo.Mod', 'Kernel.Mod', 'FileDir.Mod', 'Files.Mod',
             'Modules.Mod', 'Fonts.Mod', 'Texts.Mod', 'RS232.Mod', 'Oberon.Mod',
             'ORS.Mod', 'ORB.Mod', 'ORG.Mod', 'ORP.Mod', 'CoreLinker.Mod',
             'VDisk.Mod', 'VFileDir.Mod', 'VFiles.Mod', 'VDiskUtil.Mod'],
            working_directory=target_dir,
            search_path=[os.path.join(NOREBO_ROOT, 'Norebo'),
                         os.path.join(NOREBO_ROOT, 'Oberon'),
                         os.path.join(NOREBO_ROOT, 'Bootstrap')])

    bulk_rename(target_dir, 'rsc', 'rsx')
    norebo(['CoreLinker.LinkSerial', 'Modules', 'InnerCore'],
           working_directory=target_dir,
           search_path=[os.path.join(NOREBO_ROOT, 'Norebo'),
                        os.path.join(NOREBO_ROOT, 'Bootstrap')])
    bulk_rename(target_dir, 'rsx', 'rsc')

def rv_build_image(sources_dir):
    global top
    if top == "":
        top = "Modules"
    sources_dir  = [os.path.realpath(sources_dir), os.path.realpath(sources_dir)+'/Tests']

    target_dir = os.path.join(NOREBO_ROOT, 'imagebuild')
    os.mkdir(target_dir)
    norebo_dir = mksubdir(target_dir, 'norebo')
    compiler_dir = mksubdir(target_dir, 'compiler')
    oberon_dir = mksubdir(target_dir, 'oberon')

    logging.info('Building norebo')
    rv_build_norebo(norebo_dir)
    search_path=[compiler_dir, norebo_dir] + sources_dir
    print(search_path)

    logging.info('Building a cross-compiler')
    compile(['RVOS.Mod', 'RVAssem.Mod', 'RVOB.Mod', 'RVOG.Mod', 'RVOP.Mod'],
            working_directory=compiler_dir,
            search_path=search_path)

    # Delete all symbol files, so that we don't accidentally link against Norebo.
    bulk_delete(norebo_dir, 'smb')
    bulk_delete(compiler_dir, 'smb')

    logging.info('Compiling the complete Project Oberon 2013')
    rv_compile([fi['filename'] for fi in FILE_LIST if fi['mode'] == 'source'],
            working_directory=oberon_dir,
            search_path=search_path)

    logging.info('Linking the Inner Core')
    # Hide the rsc files, Norebo can't use them (CoreLinker knows to expect this extension)
    bulk_rename(oberon_dir, 'rsc', 'rsx')
    norebo(['RVCoreLinker.LinkDisk', top, 'Oberon.dsk'],
           working_directory=target_dir,
           search_path=[oberon_dir, norebo_dir])

    logging.info('Installing files')

    def copy(src, dst):
        return '%s=>%s' % (src, dst)

    install_args = ['Oberon.dsk']

    for fi in FILE_LIST:
        mod = fi['filename']
        if ~exclude_source:
            install_args.append(copy(mod, mod))
        if fi['mode'] == 'source':
            if ~exclude_source:
                smb = fi['filename'].replace('.Mod', '.smb')
                install_args.append(copy(smb, smb))
            rsx = fi['filename'].replace('.Mod', '.rsx')
            rsc = fi['filename'].replace('.Mod', '.rsc')
            install_args.append(copy(rsx, rsc))

    search_path=[oberon_dir, norebo_dir] + sources_dir
    norebo(['VDiskUtil.InstallFiles'] + install_args,
           working_directory=target_dir,
           search_path=search_path)

    check_args = ['Oberon.dsk']
    for fi in FILE_LIST:
        mod = fi['filename']
        check_args.append(mod)
        if fi['mode'] == 'source':
            smb = mod.replace('.Mod', '.smb')
            rsc = mod.replace('.Mod', '.rsc')
            check_args.append(smb)
            check_args.append(rsc)
        else:
            check_args.append(mod)

    logging.info('Checking files were installed correctly')
    norebo(['VDiskUtil.CheckFiles'] + check_args,
           working_directory=target_dir,
           search_path=search_path)

    logging.info('All done! Finished disk image is %s', os.path.join(target_dir, 'Oberon.dsk'))

def build_image(sources_dir):
    global top
    if top == "":
        top = "Modules"

    sources_dir  = os.path.realpath(sources_dir)

    target_dir = os.path.join(NOREBO_ROOT, 'imagebuild')
    os.mkdir(target_dir)
    norebo_dir = mksubdir(target_dir, 'norebo')
    compiler_dir = mksubdir(target_dir, 'compiler')
    oberon_dir = mksubdir(target_dir, 'oberon')

    logging.info('Building norebo')
    build_norebo(norebo_dir)

    logging.info('Building a cross-compiler')
    compile(['ORS.Mod', 'ORB.Mod', 'ORG.Mod', 'ORP.Mod'],
            working_directory=compiler_dir,
            search_path=[sources_dir, compiler_dir, norebo_dir])

    # Delete all symbol files, so that we don't accidentally link against Norebo.
    bulk_delete(norebo_dir, 'smb')
    bulk_delete(compiler_dir, 'smb')

    logging.info('Compiling the complete Project Oberon 2013')
    compile([fi['filename'] for fi in FILE_LIST if fi['mode'] == 'source'],
            working_directory=oberon_dir,
            search_path=[sources_dir, compiler_dir, norebo_dir])

    logging.info('Linking the Inner Core')
    # Hide the rsc files, Norebo can't use them (CoreLinker knows to expect this extension)
    bulk_rename(oberon_dir, 'rsc', 'rsx')
    norebo(['CoreLinker.LinkDisk', top, 'Oberon.dsk'],
           working_directory=target_dir,
           search_path=[oberon_dir, norebo_dir])

    logging.info('Installing files')

    def copy(src, dst):
        return '%s=>%s' % (src, dst)

    install_args = ['Oberon.dsk']
    install_args.extend(
        copy(fn, fn)
        for fn in sorted(os.listdir(sources_dir))
        if not fn.startswith("."))


    # This only copies over files found in the manifest. This is deliberate, and way less of a headache!
    for fi in FILE_LIST:
        mod = fi['filename']
        if ~exclude_source:
            install_args.append(copy(mod, mod))
        if fi['mode'] == 'source':
            if ~exclude_source:
                smb = fi['filename'].replace('.Mod', '.smb')
                install_args.append(copy(smb, smb))
            rsx = fi['filename'].replace('.Mod', '.rsx')
            rsc = fi['filename'].replace('.Mod', '.rsc')
            install_args.append(copy(rsx, rsc))

    norebo(['VDiskUtil.InstallFiles'] + install_args,
           working_directory=target_dir,
           search_path=[oberon_dir, sources_dir, norebo_dir])

    check_args = ['Oberon.dsk']
    for fi in FILE_LIST:
        mod = fi['filename']
        check_args.append(mod)

    logging.info('Checking files were installed correctly')
    norebo(['VDiskUtil.CheckFiles'] + check_args,
           working_directory=target_dir,
           search_path=[oberon_dir, sources_dir, norebo_dir])

    logging.info('All done! Finished disk image is %s', os.path.join(target_dir, 'Oberon.dsk'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
      '-d', '--debug', dest='debug', action='store_true', help='enable debug log output'
    )
    parser.add_argument(
      '-r', '--riscv', dest='riscv', action='store_true', help='use RISC-V compiler and sources to create disk image'
    )
    parser.add_argument(
        '-m', '--manifest', dest='manifest', type=str, default='manifest.csv', help='pass in a different manifest'
    )
    parser.add_argument(
        '-t', '--test', dest='testfile', type=str, default=None, help='pass in a file to test'
    )
    parser.add_argument(
        '-s', '--without-source', dest='remove_src', action='store_true', help='Only include executables in the image'
    )
    parser.add_argument('SOURCES')
    args = parser.parse_args()
    log_level = logging.DEBUG if args.debug else logging.INFO
    use_riscv = args.riscv
    global exclude_source
    exclude_source = args.remove_src
    if (args.manifest and args.manifest != 'manifest.csv'):
        read_file_list(args.manifest)

    # modifies -m
    # this should be documented much better, TODO...
    # also only works with RV atm, mostly because I don't really need this with R5.
    if (args.testfile):
        global FILE_LIST, top
        FILE_LIST = [{"mode":"source","filename":args.testfile}]
        top = args.testfile.replace('.Mod', '')
        print(top)

    logging.basicConfig(format='%(levelname)s: %(message)s', level=log_level)

    if not os.path.exists(args.SOURCES):
        logging.error("%s: '%s': No such file or directory", __file__, args.SOURCES)
        sys.exit(1)
    elif not os.path.isdir(args.SOURCES):
        logging.error("%s: '%s': Not a directory", __file__, args.SOURCES)
        sys.exit(1)

    if use_riscv:
        print("Building RISC-V image.")
        rv_build_image(args.SOURCES)
    else:
        print("Building original RISC-5 image.")
        build_image(args.SOURCES)


if __name__ == '__main__':
    main()
