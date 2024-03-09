# Collection of backup commands and their use-cases

For script usage, consider an `$EXCLUDED` variable that has the standard folders to exclude for system backups.

## Simple File Copy from Remote Host

### Bare Files
`scp $USER@$HOST:/path/to/source/* /path/to/destination`
### TAR Archive
`scp $USER@$HOST:/path/to/source/* - | tar -czvf /path/to/new_archive.tar.gz -T -`

---

If using `fish` shell use different glob:
`scp -r "$USER@$HOST:/path/to/source/**" /path/to/destination`

## System Backups

Additional options for system backups that work for both `tar` and `rsync`:
`--exclude` to omit non-standard files such as system resources
`one-file-system` to prevent backing up mounted file systems that aren't already excluded (above)

### `tar` for single compressed archive

This is suitable for creating a single snapshot of the running system. This is faster and generally more reliable than `rsync` in my experience for a live system.

For time-stamped system backup:
`tar -czpvf "/backup/system-state_$(hostname)_$(date +'%Y%m%d%H%M%S').tar.gz" --exclude={/backup*,/dev,/home,/lost+found,/media,/mnt,/proc,/run,/sys,/tmp,/var/lib/lxcfs,/var/lib/lxd/unix.socket,/timeshift,/swapfile} --one-file-system /`

To add parallel compression with `pigz`:
`tar --use-compress-program="pigz -p $(nproc)" -cpvf "/backup/system-state_$(hostname)_$(date +'%Y%m%d%H%M%S').tar.gz" --exclude={/backup*,/dev,/home,/lost+found,/media,/mnt,/proc,/run,/sys,/tmp,/var/lib/lxcfs,/var/lib/lxd/unix.socket,/timeshift,/swapfile} --one-file-system /`

For restoration:
`tar -xzvf /backup/system-state_HOST_TIMESTAMP.tar.gz -C /path/to/restore` (probably a chroot)

- c ... create archive
- z ... gzip
- p ... preserve permissions, ownership, etc.
- v ... verbose (progress too)
- f ... use specified file name
- x ... extract archive

### `rsync` to remote server using rsync protocol
Standard `rsync` flags: `rsync -hPa` ('rsync hectoPascal')
- h ... human-readable values
- P ... adds partial transfer and shows progress (verbose implied)
- a ... archive

Some troubleshooting suggestions:
- W ... send the whole file rather than use the delta-transfer algorithm to avoid hanging on locked/active files
- u ... if the target files are newer than the source files (possibly due to misconfigured timezones) this will allow `rsync` to skip the file

This assumes that the local host is backing itself up (as root) to a remote host. Modify the `$hostname` part of the path to avoid overwriting.

`rsync -hPaW --exclude={/backup*,/dev,/home,/lost+found,/media,/mnt,/proc,/run,/sys,/tmp,/var/lib/lxcfs,/var/lib/lxd/unix.socket,/timeshift,/swapfile} --one-file-system / rsync://$USER@$HOST/system_backups/$(hostname)_$(date +\%Y\%m\%d\%H\%M\%S)`

### `rsync` to remote server with simple versioning

Similar to the previous example except this is for maintaining a single backup of a host while preserving deletions and altered files in a `/backup_rsync` folder on the destination. The `--delete` and `--backup-dir` options are added which implies `-b` and `--delete-during` and the path is simplified to just `$hostname` without a date.

`rsync -hPaW --delete --backup-dir=backup_rsync --exclude={/backup*,/dev,/home,/lost+found,/media,/mnt,/proc,/run,/sys,/tmp,/var/lib/lxcfs,/var/lib/lxd/unix.socket,/timeshift,/swapfile} --one-file-system / rsync://$USER@$HOST/system_backups/$(hostname)`

## Data Backups

### `tar`

Fewer features than `rsync` but gets the job done:
`tar -czpvf /dev/null /path/to/source | less` for a dry run.
`tar -czpvf /path/to/destination/$ARCHIVE.tar.gz /path/to/source1 /path/to/source2` to proceed with the backup.

Alternatively you can change the directory for relative pathing (using '.' for the current directory in this case):
`tar -czpvf /path/to/destination/$ARCHIVE.tar.gz -C /path/to/source .`

### `rsync`

For assessing the changes:
`rsync -hPa --delete-after /path/to/source /path/to/destination -in | less`

Drop the `-in | less` to proceed with the backup.

*To Preserve Changed Files:*

`rsync -hPa --delete-after --backup-dir=/path/to/backups /path/to/source /path/to/destination`

## `rsync` Extra Features

For network transfers: add `-z`
For a dry run: `-in | less` (itemize changes and dry-run)
For sidestepping all file permission issues: `--no-o --no-g`

### Itemize Changes (--itemize-changes or -i)

Remember: `rsync` was designed to pull packages from mirrors as efficiently as possible.

`<: file is being transferred to the remote host (sent).`
    This means a change on the "source" directory such as when using the "--remove-source-files" option

`>: file is being transferred to the local host (received).`
    This is a normal file addition/modification on the target directory.
```
.d..t..g... ./
.f...p.g... Something.pdf
.f.....g... md5sum-2010-02-21.txt
.f...p.g... prova.rb
.d.....g... .metadata/
.f...p.g... .metadata/.lock
.f...p.g... .metadata/.log
.f...p.g... .metadata/version.ini
>f+++++++++ Parameter_Usage.txt

YXcstpoguax  path/to/file
|||||||||||
`----------- the type of update being done::
 ||||||||||   <: file is being transferred to the remote host (sent).
 ||||||||||   >: file is being transferred to the local host (received).
 ||||||||||   c: local change/creation for the item, such as:
 ||||||||||      - the creation of a directory
 ||||||||||      - the changing of a symlink,
 ||||||||||      - etc.
 ||||||||||   h: the item is a hard link to another item (requires --hard-links).
 ||||||||||   .: the item is not being updated (though it might have attributes that are being modified).
 ||||||||||   *: means that the rest of the itemized-output area contains a message (e.g. "deleting").
 ||||||||||
 `---------- the file type:
  |||||||||   f for a file,
  |||||||||   d for a directory,
  |||||||||   L for a symlink,
  |||||||||   D for a device,
  |||||||||   S for a special file (e.g. named sockets and fifos).
  |||||||||
  `--------- c: different checksum (for regular files)
   ||||||||     changed value (for symlink, device, and special file)
   `-------- s: Size is different
    `------- t: Modification time is different
     `------ p: Permission are different
      `----- o: Owner is different
       `---- g: Group is different
        `--- u: The u slot is reserved for future use.
         `-- a: The ACL information changed
```
