;; -*- lexical-binding: t; -*-

(use-package gptel
  :ensure t)

(setq-default gptel-backend (gptel-make-ollama "Ollama"
                                               :host "192.168.2.69:11434"
                                               :stream t
                                               :models '("granite4.1:8b-q8_0" "gpt-oss:20b" "gpt-oss:120b" "mistral-medium-3.5:128b" "nemotron-3-super:120b")
                                               :request-params '(:options (
									:temperature 0.7 
							 		:top_p 0.95 
									:num_ctx 1048576
									:num_predict 1048576
								))))


(setq-default gptel-model 'nemotron-3-super:120b)
