# S3 Internal Websites

Fully written and tested using [OpenTofu](https://github.com/opentofu/opentofu)

This creates the required infrastructure to serve multiple internal websites with s3 behind a single load balancer and S3 Endpoint

This module is not meant to be used in production; its goal is to serve as an example of the infrastructure required to serve internal websites using S3 that can later be accessed either by EC2 machines or by any users through a VPN.

can read more about it on my blog at: [blog.coolapso.sh](https://blog.coolapso.sh/en/posts/s3internalwebsites/)
