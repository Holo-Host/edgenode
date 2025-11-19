.PHONY: build run clean

build:
	docker rmi -f local-edgenode-unyt local-edgenode-hc-0.6.0-custom-go-pion 2>/dev/null || true
	cd tools/happ_config_file && cargo build --release
	cp tools/happ_config_file/target/release/happ_config_file docker/happ_config_file
	cd docker && ./build-images.sh local-edgenode-unyt

run: 
	docker rm -f unyt-container1 2>/dev/null || true
	docker run -it --name unyt-container1 local-edgenode-unyt

clean:
	docker rmi -f local-edgenode-unyt local-edgenode-hc-0.6.0-custom-go-pion 2>/dev/null || true