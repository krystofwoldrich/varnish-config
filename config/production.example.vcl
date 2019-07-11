# VCL version 4.0
vcl 4.0;

# Imports
import directors;

#
# Plone clients definition
#
backend client_0 {
	.host = "XXX.XXX.XXX.XXX";
	.port = "XXXX";
	.max_connections = 250;
	.connect_timeout = 500s;	
	.first_byte_timeout = 300s;
	.between_bytes_timeout  = 60s;
	.probe = {
		.url = "/";
		.interval = 5s;
		.timeout = 1 s;
		.window = 5;
		.threshold = 3;
  	}
}

backend client_1 {
	.host = "XXX.XXX.XXX.XXX";
	.port = "XXXX";
	.connect_timeout = 500s;	
	.first_byte_timeout = 300s;
	.between_bytes_timeout  = 60s;
	.probe = {
		.url = "/";
		.interval = 5s;
		.timeout = 1 s;
		.window = 5;
		.threshold = 3;
  	}
}

#
# Initialize VCL configuration
#
sub vcl_init {
	new plone = directors.round_robin();
    plone.add_backend(client_0);
    plone.add_backend(client_1);
}

#
# Purge white list
#
acl list_purge {
    "localhost";
    "127.0.0.1";
}

#
# Process incoming HTTP Request
#
sub vcl_recv {
	set req.backend_hint = plone.backend();

	set req.url = "/VirtualHostBase/http/" + req.http.host + ":80/Plone/VirtualHostRoot" + req.url;

    # Do Plone cookie sanitization, so cookies do not destroy cacheable anonymous pages
    if (req.http.Cookie) {
        set req.http.Cookie = ";" + req.http.Cookie;
        set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");
        set req.http.Cookie = regsuball(req.http.Cookie, ";(statusmessages|__ac|_ZopeId|__cp)=", "; \1=");
        set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
        set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");

        if (req.http.Cookie == "") {
            unset req.http.Cookie;
        }
    }

	if (req.method == "PURGE") {
        # Not from an allowed IP? Then die with an error.
        if (!client.ip ~ list_purge) {
            return (synth(405, "This IP is not allowed to send PURGE requests."));
        }
        return (hash);
    }

    if (req.method == "BAN") {
            # Same ACL check as above:
            if (!client.ip ~ list_purge) {
            return(synth(403, "Not allowed."));
            }
            #ban("req.url ~ " + req.url);
        ban("req.http.host == " + req.http.host +
            " && req.url == " + req.url);
            # Throw a synthetic page so the
            # request won't go to the backend.
            return(synth(200, "Ban added"));
    }

    if (req.method != "GET" &&
      req.method != "HEAD" &&
      req.method != "PUT" &&
      req.method != "POST" &&
      req.method != "TRACE" &&
      req.method != "OPTIONS" &&
      req.method != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }
    if (req.method != "GET" && req.method != "HEAD") {
        /* We only deal with GET and HEAD by default */
        return (pass);
    }
    if (req.http.Authorization || req.http.Cookie) {
        /* Not cacheable by default */
        return (pass);
    }
    return (hash);
}


#
# Process backend response
#
sub vcl_backend_response {
    # The object is not cacheable
    if (beresp.http.Set-Cookie) {
        set beresp.http.X-Cacheable = "NO - Set Cookie";
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
    } elsif (beresp.http.Cache-Control ~ "private") {
        set beresp.http.X-Cacheable = "NO - Cache-Control=private";
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
    } elsif (beresp.http.Surrogate-control ~ "no-store") {
        set beresp.http.X-Cacheable = "NO - Surrogate-control=no-store";
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
    } elsif (!beresp.http.Surrogate-Control && beresp.http.Cache-Control ~ "no-cache|no-store") {
        set beresp.http.X-Cacheable = "NO - Cache-Control=no-cache|no-store";
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
    } elsif (beresp.http.Vary == "*") {
        set beresp.http.X-Cacheable = "NO - Vary=*";
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;


    # ttl handling
    } elsif (beresp.ttl < 0s) {
        set beresp.http.X-Cacheable = "NO - TTL < 0";
        set beresp.uncacheable = true;
    } elsif (beresp.ttl == 0s) {
        set beresp.http.X-Cacheable = "NO - TTL = 0";
        set beresp.uncacheable = true;

    # Varnish determined the object was cacheable
    } else {
        set beresp.http.X-Cacheable = "YES";
    }

    # Do not cache 5xx errors
    if (beresp.status >= 500 && beresp.status < 600) {
        unset beresp.http.Cache-Control;
        set beresp.http.X-Cache = "NOCACHE";
        set beresp.http.Cache-Control = "no-cache, max-age=0, must-revalidate";
        set beresp.ttl = 0s;
        set beresp.http.Pragma = "no-cache";
        set beresp.uncacheable = true;
        return(deliver);
    }

    # TODO this one is very plone specific and should be removed, not sure if its needed any more
    if (bereq.url ~ "(createObject|@@captcha)") {
        set beresp.uncacheable = true;
        return(deliver);
    }

    return (deliver);
}

#
# Process outcomming HTTP Response
#
sub vcl_deliver {
	resp.http.Via = "varnish";
}

#
# Genereate page hash
#
sub vcl_hash {
    hash_data(req.url);
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }
    return (lookup);
}

#
# Error redirections
#
sub vcl_synth {
    if (resp.status == 720) {
        # We use this special error status 720 to force redirects with 301 (permanent) redirects
        # To use this, call the following from anywhere in vcl_recv: error 720 "http://host/new.html"
        set resp.status = 301;
        set resp.http.Location = resp.reason;
        return (deliver);
    } elseif (resp.status == 721) {
        # And we use error status 721 to force redirects with a 302 (temporary) redirect
        # To use this, call the following from anywhere in vcl_recv: error 720 "http://host/new.html"
        set resp.status = 302;
        set resp.http.Location = resp.reason;
        return (deliver);
    }

    return (deliver);
}

#
# Response on error
#
sub vcl_synth {
    set resp.http.Content-Type = "text/html; charset=utf-8";
    set resp.http.Retry-After = "5";

    synthetic( {"
            <?xml version="1.0" encoding="utf-8"?>
            <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
            <html>
              <head>
                <title>"} + resp.status + " " + resp.reason + {"</title>
              </head>
              <body>
                <h1>Error "} + resp.status + " " + resp.reason + {"</h1>
                <p>"} + resp.reason + {"</p>
                <h3>Guru Meditation:</h3>
                <p>XID: "} + req.xid + {"</p>
                <hr>
                <p>Varnish cache server</p>
              </body>
            </html>
    "} );

    return (deliver);
}
