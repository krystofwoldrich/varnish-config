# VCL version 4.0
vcl 4.0;

#
# Plone client definition
#
backend default {
	.host = "XXX.XXX.XXX.XXX";
	.port = "XXXX";
}

#
# Process incoming HTTP Request
#
sub vcl_recv {
	set req.url = "/VirtualHostBase/http/" + req.http.host + ":80/Plone/VirtualHostRoot" + req.url;
}

#
# Process outcomming HTTP Response
#
sub vcl_deliver {
	resp.http.Via = "varnish";
}
