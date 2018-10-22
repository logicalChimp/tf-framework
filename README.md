# tf-framework
basic Make framework for Terraform

This framework will provide basic support for deploying to multiple projects
(e.g. dev, test, prod), optional support for ansible-vault encrypted config
files, multiple 'service' definitions in a single Terraform project (with
their own State files so they can be managed / deployed individually), and
so on.

The project will aim to use solely Make, Bash, and Terraform commands - no
embedded Python, Ruby, etc - to simplify platform dependencies.