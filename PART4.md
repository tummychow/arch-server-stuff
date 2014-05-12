# Part 4: Domain Names

[<- Part 3](PART3.md) [Part 5 ->](PART5.md)

This part covers:

- establishing domain names on a DNS-aware router
- using a default server to prevent routing to unrecognized names

## Step 1: Local DNS Names

So far, the application servers you set up have been hosting on 127.0.0.1, aka `localhost` or `localhost.localdomain`. One problem with having both servers on the same IP/port combination is that nginx can only tell them apart by hostname. To resolve the ambiguity, the configs I showed you earlier were using a different port for each server.

But it's a pain to specify the port when you want to browse your site, and Phabricator wants a real name anyway. What you really want is a domain name for each server.

There are a number of ways you can configure this. You could edit the `/etc/hosts` file, which specifies static domain names for the current machine. If you navigate to a certain name, the machine will check the hosts file first. But that configuration has to be copied manually to other machines, or otherwise they won't recognize the hostnames. So that's no good.

On the other end of the spectrum, you can buy a real domain name on the Internet and expose your server to the whole world. But that's a pretty serious responsibility - there's no shortage of people who will attack your server, not to mention your server could potentially face much higher load now that anyone on the Internet could find it.

There is a better solution which is in between both of these extremes. You can set up a domain name that is not local to the machine itself, but not exposed to the entire Internet either, by setting up the name resolution on the gateway between those two parties: your router. To do this, you need a pretty smart router which has a DNS server built in. My router is running DD-WRT, which incorporates DNSMasq, so that's what I will use in this guide.

First, you'll need your server to be connected directly to the router's network. For a physical computer, you can just plug in an Ethernet cable or connect to the Wi-Fi or what have you. For a VirtualBox VM, you need to change the networking type to bridged. This allows VirtualBox to simulate the effect of adding your VM to the same network as the host. Assuming your host is connected directly to the router, your VM will now behave the same way.

Next, your server needs a fixed IP address. DNSMasq will map your DNS name to a single IP address, so your server needs to answer at that IP address. In the usual configuration, network clients would request an IP address from the router via DHCP, so the IP address could change. That's what you need to avoid. You can configure for static IP on the server's side, or you can set up a [static DHCP lease](http://www.howtogeek.com/69696/how-to-access-your-machines-using-dns-names-with-dd-wrt/) on the router's side. I prefer the latter.

DD-WRT provides a convenient web interface to set the static DHCP leases, as shown in that howtogeek article, but you can set them using DNSMasq's configuration files if you must (DD-WRT also has an interface to append to the config file directly). The DNSMasq command you need is `--dhcp-host`, eg `--dhcp-host=b8:88:e3:34:39:33,192.168.1.100`. This command would ensure that a device with that MAC address was always given that IP address. See [the docs](http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html) for more details.

The third part is the DNS name. When your router's DNSMasq instance sees a request for this hostname, it'll know to route the request to the IP address of the server. Use the `--address` command for this, eg `address=/gollum.lan/192.168.1.100`. This command takes a list, separated by slashes. The last item indicates the IP address we want to route to (it's the same as the fixed IP address we configured above). The other items indicate domain names, all of which will be routed to the IP address you choose. In this case, the domain name `gollum.lan` will map to the IP address 192.168.1.100. If you attempted to navigate to `http://gollum.lan`, you'd end up accessing 192.168.1.100:80. I also added the domain `phab.lan` for Phabricator.

The last part is to change the `server_name` in your nginx configuration. That allows nginx to tell the difference between `http://gollum.lan` and `http://phab.lan`, even if they were mapped to the same IP address and port. Once you've changed the `server_name` to the name you chose, you need to refresh your DNS cache, which varies depending on your browser/OS/etc. Once your DNS cache is renewed, you should be able to navigate to `http://gollum.lan` in a browser, and find the homepage of your Gollum wiki.

## Step 2: Default Servers

Having set up domain names for your sites, another interesting question arises. What if you navigate to the IP address of your server, but without using any of the server names? For example, my VM was running at `arch.lan`. I added the domain names `gollum.lan` and `phab.lan`, and then I set nginx to serve on those names. But `arch.lan` also maps to the same IP. If I navigate to `http://arch.lan` in a browser, what will show up?

The answer is that nginx serves the [*default server*](http://nginx.org/en/docs/http/request_processing.html). If you access nginx and request a hostname that does not match any of nginx's servers, it chooses a default from the servers on the port you're requesting. Normally, the default is the first server in the config file. In my case, the Gollum server was first, so `http://arch.lan` shows me the Gollum homepage.

Personally, I didn't want nginx to serve on domain names that I hadn't configured. You can prevent this default behavior by setting your own default server explicitly, using a config like this. (I already included it at the bottom of my nginx.conf.)

```nginx
server {
    server_name _;
    listen 80 default_server;
    return 444;
}
```

The name `_` will never match any real domain, so this server block only gets engaged if none of the other domain names matched. 444 is a special nginx return code, which terminates the connection immediately. Now, if I navigate to `http://arch.lan`, the hostname I'm requesting (`arch.lan`) on the port I'm requesting (80) does not match any of my servers, so it gets routed to the default. The default server returns 444, which terminates the connection, so I get nothing (which is what I wanted).
