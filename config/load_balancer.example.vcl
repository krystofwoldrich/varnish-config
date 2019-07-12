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
# Process incoming HTTP Request
#
sub vcl_recv {
	set req.backend_hint = plone.backend();

	set req.url = "/VirtualHostBase/http/" + req.http.host + ":80/Plone/VirtualHostRoot" + req.url;
}

#
# Process outcomming HTTP Response
#
sub vcl_deliver {
	resp.http.Via = "varnish";
}
