SHELL := /bin/bash
TEKTON_PIPELINE_DIR ?= $(HOME)/go/src/github.com/tektoncd/pipeline
KIND_CLUSTER_NAME ?= saiyan
KO_DOCKER_REPO ?= kind.local
PVC_NAME ?= saiyan-training-data
PIPELINE_NAME ?= saiyan-loop-training
MGBA_IMAGE ?= saiyan-trainer/mgba:latest
GENS ?= 2
DATA_DIR ?= data
BACKUP_FILE ?= $(DATA_DIR)/pvc-backup.tar.gz

.PHONY: ensure-cluster deploy-tekton deploy-pipeline ensure-infra build-image load-image ensure-image train resume status clean-runs save-data load-data delete-cluster

# Ensure Kind cluster exists, create if missing
ensure-cluster:
	@if kind get clusters 2>/dev/null | grep -q "^$(KIND_CLUSTER_NAME)$$"; then \
		echo "==> Kind cluster '$(KIND_CLUSTER_NAME)' already exists."; \
	else \
		echo "==> Creating Kind cluster '$(KIND_CLUSTER_NAME)'..."; \
		kind create cluster --name $(KIND_CLUSTER_NAME); \
	fi
	@kubectl config use-context kind-$(KIND_CLUSTER_NAME)

# Build mGBA Docker image
build-image:
	@echo "==> Building mGBA Docker image..."
	docker build -t $(MGBA_IMAGE) -f docker/Dockerfile .

# Load mGBA image into Kind cluster
load-image: ensure-cluster
	@echo "==> Loading mGBA image into Kind..."
	kind load docker-image $(MGBA_IMAGE) --name $(KIND_CLUSTER_NAME)

# Ensure mGBA image is built and loaded into Kind
ensure-image: ensure-cluster
	@if docker exec $(KIND_CLUSTER_NAME)-control-plane crictl images 2>/dev/null | grep -q "saiyan-trainer/mgba"; then \
		echo "==> mGBA image already in Kind cluster."; \
	else \
		if docker images $(MGBA_IMAGE) -q 2>/dev/null | grep -q .; then \
			echo "==> mGBA image exists locally, loading into Kind..."; \
			kind load docker-image $(MGBA_IMAGE) --name $(KIND_CLUSTER_NAME); \
		else \
			$(MAKE) build-image; \
			kind load docker-image $(MGBA_IMAGE) --name $(KIND_CLUSTER_NAME); \
		fi; \
	fi

# Deploy Tekton Pipeline with Loop feature (feat/pipeline-iteration branch)
deploy-tekton: ensure-cluster
	@if kubectl get deployment tekton-pipelines-controller -n tekton-pipelines &>/dev/null; then \
		echo "==> Tekton already deployed, skipping. Use 'make deploy-tekton-force' to redeploy."; \
	else \
		$(MAKE) deploy-tekton-force; \
	fi

deploy-tekton-force: ensure-cluster
	@echo "==> Deploying Tekton with Loop feature from $(TEKTON_PIPELINE_DIR)..."
	cd $(TEKTON_PIPELINE_DIR) && git checkout feat/pipeline-iteration
	kubectl create namespace tekton-pipelines --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f $(TEKTON_PIPELINE_DIR)/config/300-crds/
	cd $(TEKTON_PIPELINE_DIR) && \
		KO_DOCKER_REPO=kind.local KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) \
		ko apply --platform=linux/arm64 -f config/
	@echo "==> Enabling alpha API fields..."
	kubectl -n tekton-pipelines patch configmap feature-flags \
		--type merge -p '{"data":{"enable-api-fields":"alpha"}}'
	@echo "==> Patching CRDs for Loop feature..."
	kubectl patch crd pipelineruns.tekton.dev --type=json \
		-p='[{"op":"add","path":"/spec/versions/0/schema/openAPIV3Schema/properties/status/x-kubernetes-preserve-unknown-fields","value":true}]'
	kubectl patch crd pipelines.tekton.dev --type=json \
		-p='[{"op":"add","path":"/spec/versions/0/schema/openAPIV3Schema/properties/spec/x-kubernetes-preserve-unknown-fields","value":true}]'
	@echo "==> Waiting for controller..."
	kubectl wait --for=condition=ready pod \
		-l app=tekton-pipelines-controller \
		-n tekton-pipelines --timeout=120s
	@echo "==> Tekton with Loop feature deployed."

# Ensure PVC exists and has training data (loads backup if available and PVC is empty)
ensure-pvc: ensure-cluster
	@if kubectl get pvc $(PVC_NAME) &>/dev/null; then \
		echo "==> PVC '$(PVC_NAME)' already exists."; \
	else \
		echo "==> Creating PVC '$(PVC_NAME)'..."; \
		kubectl apply -f - <<< '{"apiVersion":"v1","kind":"PersistentVolumeClaim","metadata":{"name":"$(PVC_NAME)"},"spec":{"accessModes":["ReadWriteOnce"],"resources":{"requests":{"storage":"2Gi"}}}}'; \
		if [ -f "$(BACKUP_FILE)" ]; then \
			echo "==> New PVC + local backup found. Loading training data..."; \
			$(MAKE) load-data; \
		fi; \
	fi

# Deploy the saiyan training pipeline (only the Pipeline, not the PipelineRun template)
deploy-pipeline: deploy-tekton
	@kubectl apply -f <(sed '/^---$$/,$$d' k8s/tekton/pipeline-loop.yaml)

# Full infrastructure: cluster + tekton + pvc + pipeline + image
ensure-infra: deploy-pipeline ensure-pvc ensure-image

# Start fresh multi-island training (4 islands)
train: ensure-infra
	@for i in 1 2 3 4; do \
		echo "==> Launching island-$$i..."; \
		sed -n '/^---$$/,$$p' k8s/tekton/pipeline-loop.yaml | \
		sed "s/run-001/island-$$i/g" | \
		sed "s/generateName: saiyan-training-/generateName: saiyan-island-$$i-/" | \
		sed 's/volumeClaimTemplate:/persistentVolumeClaim:\n        claimName: $(PVC_NAME)/' | \
		sed '/spec:/a\\  timeouts:\n    pipeline: "0"\n    tasks: "0"\n    finally: "0"' | \
		kubectl create -f -; \
	done
	@echo "==> 4 islands launched."

# Resume training from best island checkpoint
# Usage: make resume GENS=2
resume: ensure-infra
	@./scripts/resume-training.sh $(GENS)

# Check training status across all islands
status:
	@kubectl get pipelineruns --no-headers 2>/dev/null | tail -10
	@echo ""
	@kubectl run status-check --image=busybox --rm -i --restart=Never \
		--overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"$(PVC_NAME)"}}],"containers":[{"name":"s","image":"busybox","command":["sh","-c","for island in $$(ls /workspace/output/ 2>/dev/null); do [ -d /workspace/output/$$island/checkpoints ] || continue; LATEST=$$(ls /workspace/output/$$island/checkpoints/gen_*.json 2>/dev/null | sed \"s/.*gen_//;s/.json//\" | sort -n | tail -1); echo \"$$island: gen $$LATEST\"; done"],"volumeMounts":[{"name":"data","mountPath":"/workspace"}]}]}}' 2>/dev/null

# Save PVC training data to local disk
save-data:
	@mkdir -p $(DATA_DIR)
	@echo "==> Saving PVC data to $(BACKUP_FILE)..."
	@kubectl run pvc-save --image=busybox --restart=Never \
		--overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"$(PVC_NAME)"}}],"containers":[{"name":"save","image":"busybox","command":["sh","-c","tar czf /tmp/pvc-backup.tar.gz -C /workspace output && echo DONE && sleep 120"],"volumeMounts":[{"name":"data","mountPath":"/workspace"}]}]}}' 2>/dev/null
	@kubectl wait --for=condition=Ready pod/pvc-save --timeout=120s 2>/dev/null
	@sleep 3
	@kubectl cp pvc-save:/tmp/pvc-backup.tar.gz $(BACKUP_FILE) 2>/dev/null
	@kubectl delete pod pvc-save --force 2>/dev/null
	@echo "==> Saved $$(du -h $(BACKUP_FILE) | cut -f1) to $(BACKUP_FILE)"

# Load training data from local backup to PVC
load-data: ensure-pvc
	@if [ ! -f "$(BACKUP_FILE)" ]; then \
		echo "ERROR: No backup found at $(BACKUP_FILE)"; \
		echo "Run 'make save-data' first."; \
		exit 1; \
	fi
	@echo "==> Loading $(BACKUP_FILE) to PVC..."
	@kubectl run pvc-load --image=busybox --restart=Never \
		--overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"$(PVC_NAME)"}}],"containers":[{"name":"load","image":"busybox","command":["sh","-c","echo READY && sleep 300"],"volumeMounts":[{"name":"data","mountPath":"/workspace"}]}]}}' 2>/dev/null
	@kubectl wait --for=condition=Ready pod/pvc-load --timeout=60s 2>/dev/null
	@kubectl cp $(BACKUP_FILE) pvc-load:/tmp/pvc-backup.tar.gz 2>/dev/null
	@kubectl exec pvc-load -- tar xzf /tmp/pvc-backup.tar.gz -C /workspace 2>/dev/null
	@kubectl delete pod pvc-load --force 2>/dev/null
	@echo "==> Training data restored to PVC."

# Clean up completed/failed PipelineRuns (keeps data on PVC)
clean-runs:
	@kubectl get pipelineruns --no-headers | awk '{print $$1}' | xargs -I{} kubectl delete pipelinerun {} 2>/dev/null || true
	@echo "==> PipelineRuns cleaned up. Training data preserved on PVC."

# Delete the Kind cluster
delete-cluster:
	@echo "==> Deleting Kind cluster '$(KIND_CLUSTER_NAME)'..."
	@kind delete cluster --name $(KIND_CLUSTER_NAME)
