# README

This guide covers my experiment to set up an all-purpose applications server. Some interesting facts about my server:

- The server is founded on Arch Linux.
- It uses nginx as its main HTTP server. I don't know anything about Apache, so don't ask me how to use that instead. I don't know a lot about nginx either, but hey, I made it work, so I'm not totally incompetent!
- I take advantage of my router, which runs DD-WRT (with DNSMasq), to resolve local DNS names to the server. This lets me protect the server behind my router's NAT while still getting pretty domain names.

What's on the server?

- Gollum: a wiki backed by a Git repository of text files on disk. Engineered by GitHub and trivial to edit, in a text editor or over a Sinatra-powered web interface.
- Phabricator: a comprehensive open-source project management suite written in PHP, tracing its origins back to Facebook.

I wrote this down for my own reference, and it's on GitHub in case anyone else finds it useful. I'm not a sysadmin, nor would I pretend to be one, but I definitely learned a lot writing this guide, and I've followed it multiple times across multiple virtual machines without a hitch. If you use Ubuntu, you're probably used to having a tutorial for everything, because *everyone* writes tutorials for Ubuntu. Arch has a great community, but in general we aren't so fortunate, so here's my attempt to give back.

## Requirements

The basic system requirement is an Arch Linux computer with `base` and `base-devel` installed. base-devel is needed to compile packages and gems. If you want fancy DNS names, you'll need somewhere to register them. For a local installation, a DD-WRT router like mine is enough. This guide is not about [how to install Arch Linux](https://wiki.archlinux.org/index.php/Beginners%27%20guide) or [how to install DD-WRT](http://www.dd-wrt.com/site/support/router-database), so you should do that stuff first.

I originally planned to do this on a [Raspberry Pi](http://www.raspberrypi.org/) (lacking in power but dirt cheap). However, my raspi's ethernet controller went kaput a few weeks ago. I'm waiting for a [Cubieboard2](http://docs.cubieboard.org/products/start#a20-cubieboard) (two ARM cores, native SATA, about twice the cost of a raspi), so in the meantime, I tested this guide on a VirtualBox VM. You can connect the VM directly to your router (well, simulate the effect) using its bridged networking mode, which is important if you want to map a DNS name to a server inside the VM.

Because I use my own computer for the server and host it behind a NAT, security is not the biggest concern for me. I don't forward any of the server's ports to the Internet at large. If you do plan on exposing this server to the world, you probably need to be more careful than I am. Consult with an expert. I'm not responsible for any bad stuff that happens to you if your server gets compromised.

## Organization

This guide started to get pretty big after a while, and huge Markdown files are hard to work with (too much scrolling), so I broke it into pieces.

- [Part 1](part1) - basic requirements. Set up nginx and ssh, get the show on the road.
- [Part 2](part2) - Gollum. Passenger makes this part easy. I've got a Unicorn configuration as well, which seems to work okay.
- [Part 3](part3) - Phabricator. Phabricator also has lots of configuration, some of which I will cover, and some of which is a work in progress.
- [Part 4](part4) - Domain names. Use DNSMasq on your router for nice local DNS names. Also has a brief note on nginx default servers.
- [Part 5](part5) - SSL. Establish your own certificate authority and use it to assign SSL certificates to your application servers.

Why are the parts ordered the way they are? Mainly because that's the order that I did things. I've tried to make the parts independent, so if you want to set up Phabricator but not Gollum, you don't *have* to read Part 2.

## License

This content uses the [BSD 3-clause license](LICENSE.md). I welcome contributions and improvements, but if you screw up your system following my instructions, it's not my fault or my problem.
