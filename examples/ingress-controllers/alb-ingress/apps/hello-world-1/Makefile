include .make.env

.PHONY: build test check run mock clean

build:
	docker build -t $(IMAGE_NAME) .

run: 
	docker run -dp $(HOST_PORT):$(CONTAINER_PORT) $(IMAGE_NAME)

test:
	# Test is not applicable here, but required by pipeline
	exit 0

mock: clean run

clean: rm-containers rm-images

check: mock
	./bin/check $(HOST_PORT)
	@$(MAKE) clean


# ================================================================================
# Custom (helper) Make targets go below here
# ================================================================================

.PHONY: rm-containers rm-images


rm-containers:
	-@ docker container ls -aq -f "status=running" -f "label=lp-service-id=$(LP_SERVICE_ID)" | xargs -I {} docker container kill {}
	-@ docker container ls -aq -f "status=exited" -f "label=lp-service-id=$(LP_SERVICE_ID)" | xargs -I {} docker container rm {}

rm-images:
	-@ docker image ls -aq -f "dangling=true" -f "label=lp-service-id=$(LP_SERVICE_ID)" | xargs -I {} docker image rm -f {}

deploy:
	@$(MAKE) build && $(MAKE) check && aws-vault exec rv-lp-sandbox aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 805470640934.dkr.ecr.us-west-2.amazonaws.com && docker tag lonelyplanet/$(LP_SERVICE_ID):latest 805470640934.dkr.ecr.us-west-2.amazonaws.com/lonelyplanet/$(LP_SERVICE_ID):latest && docker push 805470640934.dkr.ecr.us-west-2.amazonaws.com/lonelyplanet/$(LP_SERVICE_ID):latest && aws-vault exec rv-lp-sandbox -- kubectl apply -f kubernetes && aws-vault exec rv-lp-sandbox -- kubectl rollout restart deployment/$(LP_SERVICE_ID)

