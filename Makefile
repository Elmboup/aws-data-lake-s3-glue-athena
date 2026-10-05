SHELL := /bin/bash

.PHONY: bootstrap deploy run check

bootstrap:
	bash scripts/bootstrap_s3.sh

deploy:
	bash scripts/deploy_glue.sh

run:
	bash scripts/run_pipeline.sh

check:
	python3 -m py_compile src/glue/raw_to_silver.py
	bash -n scripts/bootstrap_s3.sh
	bash -n scripts/deploy_glue.sh
	bash -n scripts/run_pipeline.sh
