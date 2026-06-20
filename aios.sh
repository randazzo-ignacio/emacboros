#!/usr/bin/env bash

source config.sh

podman run \
	 --rm -it --name emacs-ai-os \
	-e GEMINI_API_KEY \
	--network host -v ~/.emacs.d:/root/.emacs.d:Z \
	-v ~/.ssh:/root/.ssh:ro,Z \
	silex/emacs:30-alpine
