# Kubernetes Marketplace

A full-stack marketplace application deployed on Kubernetes with **Flask** (backend), **React** (frontend), and **PostgreSQL** (persistent database).

## Architecture

```
┌─────────────┐     /api/*      ┌─────────────┐     SQL      ┌─────────────┐
│  Frontend   │ ──────────────► │   Backend   │ ───────────► │  PostgreSQL │
│  Pod (React)│                 │  Pod (Flask)│              │  + PVC 5Gi  │
└─────────────┘                 └─────────────┘              └─────────────┘
     NodePort :30080
```

| Component  | Technology              | Pod        |
|-----------|-------------------------|------------|
| Frontend  | React + Vite + Nginx    | `frontend` |
| Backend   | Flask + Gunicorn + JWT  | `backend`  |
| Database  | PostgreSQL 16           | `postgres` |

## Features

- **Marketplace** — public product catalog
- **User control** — register, login, JWT authentication
- **Admin panel** — administrators can add and delete products
- **Persistent storage** — PostgreSQL data stored on a PersistentVolumeClaim

## Project Structure

```
k8s_sellerpage/
├── scripts/
│   ├── install-kubeadm.sh   # Install Kubernetes on Ubuntu VM
│   └── deploy.sh            # Build images and deploy to cluster
├── backend/                 # Flask API
├── frontend/                # React SPA
└── k8s/                     # Kubernetes manifests
```

---

## 1. Install Kubernetes (Ubuntu VM)

On your Ubuntu virtual machine, run:

```bash
chmod +x scripts/install-kubeadm.sh
sudo ./scripts/install-kubeadm.sh init
```

This script will:

1. Disable swap and configure kernel modules
2. Install containerd
3. Install kubeadm, kubelet, and kubectl (v1.29)
4. Initialize a single-node control plane
5. Install the Flannel CNI plugin

Other commands:

```bash
sudo ./scripts/install-kubeadm.sh prepare   # Install packages only
sudo ./scripts/install-kubeadm.sh reset     # Tear down cluster
sudo ./scripts/install-kubeadm.sh worker <token> <cp-ip:6443>  # Join as worker
```

Copy kubeconfig for your user:

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

---

## 2. Deploy the Marketplace

From a machine with Docker and kubectl access to the cluster:

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

Or step by step:

```bash
# Build images
docker build -t marketplace-backend:latest backend/
docker build -t marketplace-frontend:latest frontend/

# Load into minikube/kind (if applicable)
minikube image load marketplace-backend:latest
minikube image load marketplace-frontend:latest

# Deploy
kubectl apply -k k8s/
```

Access the app at **http://\<node-ip\>:30080**

### Default Admin Credentials

| Field    | Value                    |
|----------|--------------------------|
| Email    | `admin@marketplace.local` |
| Password | `admin123`               |

Change these in `k8s/secrets.yaml` before deploying to production.

---

## 3. Local Development (without Kubernetes)

### Backend

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

export DB_HOST=localhost DB_USER=marketplace DB_PASSWORD=marketplace DB_NAME=marketplace
# Start PostgreSQL locally, then:
gunicorn --bind 0.0.0.0:5000 wsgi:app
```

### Frontend

```bash
cd frontend
npm install
npm run dev
```

Open http://localhost:3000 — API requests are proxied to the backend.

---

## API Endpoints

| Method | Path                  | Auth   | Description          |
|--------|-----------------------|--------|----------------------|
| POST   | `/api/auth/register`  | No     | Register user        |
| POST   | `/api/auth/login`     | No     | Login                |
| GET    | `/api/auth/me`        | JWT    | Current user         |
| GET    | `/api/products/`      | No     | List products        |
| GET    | `/api/products/:id`   | No     | Get product          |
| GET    | `/api/admin/products` | Admin  | List all (admin)     |
| POST   | `/api/admin/products` | Admin  | Create product       |
| PUT    | `/api/admin/products/:id` | Admin | Update product   |
| DELETE | `/api/admin/products/:id` | Admin | Delete product   |

---

## Kubernetes Resources

```bash
kubectl -n marketplace get all
kubectl -n marketplace get pvc          # Persistent volume claim
kubectl -n marketplace logs deployment/backend
kubectl -n marketplace logs deployment/frontend
```

To remove everything:

```bash
kubectl delete -k k8s/
```

Note: deleting the namespace also removes the PVC and all stored data.
