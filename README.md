# backup
scripts used to do backups

You can use these scripts to implement a backup for your linux based computer - server or desktop.
It is really basic and simple, using rsync and hardlink copys to implement space saving backup rotations.

It is based on a project for servers, and with this I try to adapt it to a personal desktop/laptop
environment. The basic difference is that a laptop does not run all the time, and also might not run
long enough to do a successfull backup. That is why the script keeps trying untill it is successfull.
Also, the rotator on the server checks if the client was successfull bevor it attempts to rotate.


ROADMAP:
=======
* count retries and stop after a certain number
* Add multilang support.


