from diagrams import Diagram, Cluster, Edge
from diagrams.gcp.network import LoadBalancing
from diagrams.gcp.compute import GKE, ComputeEngine
from diagrams.gcp.storage import GCS
from diagrams.onprem.client import Users

graph_attr = {
    "bgcolor": "transparent",
    "dpi": "150",
    "pad": "0.8",
    "fontsize": "14",
}

public_subnet_attr = {
    "bgcolor": "#fff3e0",
    "style": "dashed",
    "pencolor": "#e65100",
}

with Diagram(
    "",
    show=False,
    filename="architecture",
    outformat="png",
    direction="LR",
    graph_attr=graph_attr,
):
    internet = Users("Internet")
    lb = LoadBalancing("HTTP\nLoad Balancer")

    with Cluster("GCP Project"):
        with Cluster("VPC Network"):
            with Cluster("Private Subnet\n10.0.2.0/24"):
                gke = GKE("GKE Cluster\nbucket-list app")

            with Cluster("Public Subnet\n10.0.1.0/24\nSSH open to 0.0.0.0/0", graph_attr=public_subnet_attr):
                vm = ComputeEngine("MongoDB VM\nUbuntu 22.04\nMongoDB 6.0")

        bucket = GCS("GCS Backup\nBucket (PUBLIC)")

    internet >> lb >> gke
    internet >> Edge(label="SSH :22", style="dashed", color="#e65100") >> vm
    internet >> Edge(label="public read", style="dashed", color="#e65100") >> bucket
    gke >> Edge(headlabel="port 27017  ", labeldistance="2.5") >> vm
    vm >> Edge(label="daily cron\nbackup", style="dashed") >> bucket
