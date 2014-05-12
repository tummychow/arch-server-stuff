# Part 5: SSL

[<- Part 4](PART4.md) Part 6 ->

This part covers:

- creating your own certificate authority to sign SSL certificates
- creating certificates for each application server
- configuring nginx to serve the sites over HTTPS using those certificates
- adding SSL to your default server

## Step 1: Creating a CA

Brief review of what SSL/TLS certificates are for: the server communicates with the client using a public/private keypair to encrypt their communications. To prove that it's actually the server and not an impersonator, the keypair is accompanied by a certificate that ties it to the domain name that hosts the keypair. To ensure the certificate is also legitimate, it's signed using yet another keypair. That keypair needs a certificate too (to prove that the signing party is legitimate), and so on. Eventually, you get to a certificate that is signed by its own keypair (a self-signed certificate), the root. The root typically belongs to a corporation that is trusted for its security, and trust propagates transitively through the certificate chain, down to the certificate used by your domain name. In practice, you need to pay an authority to sign your key - what you're paying for is the trust that clients place in the authority. Obviously, it's cheaper to set up certificates yourself if you don't need to serve the whole Internet.

You can give each of your domain names a self-signed certificate, but I think it's more fun to set up a real certificate chain with your own certificate authority. Then each of your domains will use a key that is signed by your authority, giving a simple two-part chain of trust. You can add your custom root certificate to your browser's list of trusted certificates, and then transparently access your domains over HTTPS as if your certificate was legit. (Cryptographically speaking, it is legit, but you're not a trusted CA, so the browser won't recognize the root certificate unless you add it yourself.)

Even though your domain names are all on the same IP and port, nginx can tell which certificate to serve to the client based on the requested hostname, via TLS SNI. With Arch Linux's openssl and nginx-passenger packages, this behavior will work out of the box. You can check this on other distros with `nginx -V`.

To start, you need to generate the CA's keypair and certificate. Getting a certificate takes multiple steps. First, you have to generate the keypair that the certificate will apply to. I used a 4096-bit RSA key. The keys are valuable from a security standpoint, so you should make them inaccessible to other users. (You can also remove access for the folders= containing the keys.) The signing key is particularly valuable, since it is the root of your trust chain. You can encrypt the key for bonus security, and then it can only be accessed with a password. For reasons I will explain later, the server keys cannot be encrypted, but you can encrypt the signing key.

```bash
# you could also use the older genrsa command
$ openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out signer.pem -pass stdin
# enter a password
$ chown root signer.pem # seriously, just generate the key as root
$ chmod 400 signer.pem
```

Next, you need a certificate signing request. This file would be sent to a real CA, to ask them to sign your key. The request contains the key in question, plus some important metadata about the key (particularly the domain name it will apply to). The request you're about to make applies to the signing key, so the metadata is not really important. Make sure to leave the [challenge password](http://serverfault.com/a/266258) blank. If you ever lost your certificate, a real CA could use the password to test if you were the real owner, but that's not relevant here.

```bash
# create certificate signing request (will be prompted for values)
# press enter to skip the blank ones
$ openssl req -new -key signer.pem -out signer.csr
You are about to be asked to enter information that will be incorporated
into your certificate request.
What you are about to enter is what is called a Distinguished Name or a DN.
There are quite a few fields but you can leave some blank
For some fields there will be a default value.
If you enter '.', the field will be left blank.
-----
Country Name (2 letter code) [AU]:CA
State or Province Name (full name) [Some-State]:Ontario
Locality Name (eg, city) []:
Organization Name (eg, company) [Internet Widgits Pty Ltd]:Stephen Jung
Organizational Unit Name (eg, section) []:Certificate Authority
Common Name (e.g. server FQDN or YOUR name) []:arch.lan
Email Address []:

Please enter the following 'extra' attributes
to be sent with your certificate request
A challenge password []:
An optional company name []:
```

Finally, you need to sign this request, to generate the actual certificate. As I said, the certificate is self-signed, so you will sign it using the `-signkey` flag. The expiry date for a root certificate is usually longer than for the children, so I set it to about 5 years, but honestly it doesn't matter when you're signing it yourself.

```bash
$ openssl x509 -req -days 1826 -in signer.csr -signkey signer.pem -out signer.crt
$ rm signer.csr # no longer needed
```

`signer.pem` is the CA's signing key, and `signer.crt` is the CA's certificate. This certificate will form the root of your trust chain.

## Step 2: Child Certificates

Now you need to generate keys and certificate requests for each application server. nginx uses the server's key to encrypt communication with the client. You can't place a password on this key, because nginx's master process needs to read the key into memory before using it. If the key was encrypted, nginx would have to ask you for the password each time it started up, in order to decrypt the key. Also remember that the signing request needs to have the Common Name set to the domain it covers. I'm hosting Gollum on `gollum.lan` and Phabricator on `phab.lan` (see [part 4](PART4.md)), so those are the names I'm using. The other metadata is not important for this situation.

```bash
$ openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out phab.pem
$ chown root phab.pem
$ chmod 400 phab.pem

$ openssl req -new -key phab.pem -out phab.csr
You are about to be asked to enter information that will be incorporated
into your certificate request.
What you are about to enter is what is called a Distinguished Name or a DN.
There are quite a few fields but you can leave some blank
For some fields there will be a default value.
If you enter '.', the field will be left blank.
-----
Country Name (2 letter code) [AU]:CA
State or Province Name (full name) [Some-State]:Ontario
Locality Name (eg, city) []:
Organization Name (eg, company) [Internet Widgits Pty Ltd]:Stephen Jung
Organizational Unit Name (eg, section) []:Phabricator
Common Name (e.g. server FQDN or YOUR name) []:phab.lan # this must match the domain name!
Email Address []:

Please enter the following 'extra' attributes
to be sent with your certificate request
A challenge password []: # leave this blank as before
An optional company name []:
```

Now you need to sign those requests. The root certificate was self-signed, but in this case, the signing key and the certificate's key are different. Therefore, the options for the signing command are also different. You also need a serial number file associated with the signing authority, so that each certificate you sign has a unique serial number. OpenSSL can generate that for you.

```bash
# generates a serial number file, signer.srl
$ openssl x509 -req -in phab.csr -out phab.crt -days 730 -CA signer.crt -CAkey signer.pem -CAcreateserial
# use the same serial file to get another serial number for the next certificate
$ openssl x509 -req -in gollum.csr -out gollum.crt -days 730 -CA signer.crt -CAkey signer.pem -CAserial signer.srl
$ rm phab.csr gollum.csr
```

This gives you a keypair, `phab.pem`, and a certificate for that keypair, `phab.crt` (and same for Gollum).

## Step 3: Hosting Certificates

The last step is to tell nginx how to serve the certificates to a client. You first need to configure nginx for SSL. My [nginx.conf](nginx.nginxconf) has some reasonable settings for those that don't really care about security. The OpenSSL cipher list I'm using comes from [Mozilla](https://wiki.mozilla.org/Security/Server_Side_TLS#Nginx), and it favors ciphers with perfect forward secrecy. I'm not a cryptographer, so I won't try to explain what that means, but to use those ciphers, you need a parameter:

```bash
# this takes 20-60 seconds on my system, ymmv
$ openssl dhparam -out dhparam.pem 2048
$ chown root dhparam.pem
$ chmod 400 dhparam.pem
```

nginx can't pass just the certificate for the server - the client needs to see the entire chain of trust, to determine whether or not the root certificate is trustworthy. So nginx has to be [configured](http://nginx.org/en/docs/http/configuring_https_servers.html) to pass along the entire chain. This is accomplished by appending the signing certificate to the signee, all the way to the root. If the chain was several links long, you would concatenate several certificates in this manner. The domain's certificate is at the top, and the root certificate is at the bottom. *The order matters!* One more thing - if you [omit the root certificate](https://community.qualys.com/thread/11026), clients will check their list of trusted root certs to see if any of those trusted certificates are the root of your partial trust chain. Therefore, if your root cert was actually trustworthy, you could exclude it from the chain.

```bash
$ cat phab.crt signer.crt > phab.chain.crt
$ cat gollum.crt signer.crt > gollum.chain.crt
```

Then, in the server block, add a `listen 443 ssl;` directive, which enables encryption on port 443 (the normal port for HTTPS). You will also need the `ssl_certificate_key` set to the keypair for that domain name, eg `ssl_certificate_key phab.pem;`. The `ssl_certificate` has to be set to the *chained* certificate for that key, eg `ssl_certificate phab.chain.crt`. The signing key `signer,pem` is not needed, and can be moved off the server (or even deleted, if you aren't going to sign any more certificates with it). Here's the complete example:

```nginx
server {
    server_name gollum.lan;
    listen 80;

    listen 443 ssl;
    ssl_certificate /root/ssl/phab.chain.crt;
    ssl_certificate_key /root/ssl/phab.pem;

    root /home/peon/gollum/public;

    passenger_root /usr/lib/passenger;
    passenger_ruby /usr/bin/ruby;
    passenger_enabled on;
}
```

Notice how one server can listen on both port 80 (HTTP) and port 443 (HTTPS) at the same time. If you wish, you can disable HTTP service by removing the `listen 80;` directive. Then, the server will only respond to HTTPS requests. You could also move the `listen 80;` to another server, which would provide a redirect to the HTTPS server, like this:

```nginx
server {
    server_name gollum.lan;
    listen 80;
    return 301 https://gollum.lan$request_uri;
}
```

The `server_name` is the same, but this one listens on port 80 and the other one would only listen on port 443. Any accesses to the HTTP server would return a 301, redirecting to the HTTPS server.

Phabricator's base URI is affected by the use of HTTPS. You would have to change it from `http://phab.lan` to `https://phab.lan`. Of course, if you didn't configure this setting, then Phabricator will host on any FQDN, no modifications required.

I'm not sure about how Unicorn (and reverse proxies in general) respond to the use of HTTPS. I *think* that, in my configuration, nginx is handling the SSL, and forwarding HTTP (without encryption) to the Unicorn socket. I was able to access Gollum over HTTPS without difficulty, so I guess it works? Suggestions welcome.

## Step 4: Default Server with SSL

In part 4, I set up the nginx default server so that requests for an unrecognized hostname on port 80 would be refused. If I requested `http://arch.lan`, I'd get no connection. But what if I request `https://arch.lan`?

The HTTPS request is over port 443 by default. The default server that was added in the last part only listens on port 80. So nginx looks for one of your servers on port 443 to fulfill the request. In my case, I end up with Gollum again. To fix this, you need to add an SSL-enabled default server on that port:

```nginx
server {
    server_name _;
    listen 80 default_server;

    listen 443 ssl default_server;
    ssl_certificate /root/ssl/arch.chain.crt;
    ssl_certificate_key /root/ssl/arch.pem;

    return 444;
}
```

The default server must be using SSL on port 443, since the other servers are using SSL on port 443. Therefore, we also need an SSL key and certificate for the default server. I generated another keypair for that purpose. You could probably recycle one of your other certificates if you were lazy, but some clients will complain that the domain name of the certificate does not match the domain name of the target host.

If you don't turn on SSL for the default server, but still attach it to port 443, then all your servers on port 443 will be borked. nginx will receive a request on port 443 and won't know whether it should use SSL or not, so it has to give up. This results in an error along the lines of "connection interrupted". In other words, if there's one server on port 443 using SSL, all the others on port 443 have to use SSL as well, even the default server.
