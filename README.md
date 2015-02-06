# backup
Scripts for creating a backup on a linux based device.

You can use these scripts to implement a backup for your linux based computer - server or desktop.
It is really basic and simple, using rsync and hardlink copys to implement space saving backup rotations.

It is based on a project for servers, and with this I try to adapt it to a personal desktop/laptop
environment. The basic difference is that a laptop does not run all the time, and also might not run
long enough to do a successfull backup. That is why the script can keep trying untill it is successfull.
Also, the rotator on the server checks if the client was successfull bevor it attempts to rotate.

It is currently rather specific to my personal setup (e.g. mounting backup device via samba ...), so
the general usefullness might be limited without a little bit of shell scripting from your side.
Patches are welcome :)


INSTALLING
==========
Client
------
Put backup_client.sh and backup_client.conf somewhere suitable (e.g. /usr/local/bin and 
/usr/local/etc respectivly). In backup_client.sh, edit CONFIG_FILE so that it contains the
full path to backup_client.conf.

If you want to monitor the status of the backup via web browser, put status.html somewhere
where your browser can find it. In status.html, edit the path to the backup_status.txt,
so that it points to the acutal status file (see backup_client.conf).

Now edit backup_client.conf so that if fits your environment.

Create a cronjob that executes backup_client.sh. 
If your client runs all day, it should be enough to call backup_client.sh once a day.
If its not forseeable, when and for how long your client might run (e.g. a personal 
laptop), it might be a good idea to run backup_client.sh more frequent, e.g. every 5 
minutes. Bevor it starts the backup, it will check if it was already successfull on that
day, and also if a previous invocation of itself is still active. In any of these cases,
it will exit and do nothing, so no matter how often you run that script, it will only
create a backup once per day.
The idea behind this behaviour is that your laptop might be shut down bevor the backup
finished, but might be powered on again at a later hour the same day, so the backup
could be finished. rsync will take care of only transfering things that have changed.

The backup device is currently a samba share that gets mounted. One could also rsync to
the backup server directly, which might be preferable, but my personal backup device
does not support rsync, so I mount the samba share locally, and do rsync locally.
It should be easy to use other backup devices.

Server
------
Put backup_server.sh and backup_server.conf somewhere suitable (e.g. /usr/local/bin and 
/usr/local/etc respectivly). In backup_server.sh, edit CONFIG_FILE so that it contains the
full path to backup_server.conf.

Now edit backup_server.conf so that if fits your environment.

Create a cronjob that executes backup_server.sh, at least once a day. It will only
rotate a backup once a day, so if you want immediate rotation after the backup, call
it every few minutes, it will check if the backup was already rotated today.

ROADMAP:
=======
* merge backup_status.txt and status.html
* count retries and stop after a certain number
* Add multilang support for status.html.

