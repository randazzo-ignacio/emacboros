#!/usr/bin/env bash

podman run \
	 --rm -it --name emacs-ai-os \
	-v ~/.emacs.d:/root/.emacs.d:Z \
	silex/emacs:30-alpine