module "vpc" {
  source             = "../modules/vpc"
  region             = var.region
  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  public_cidrs       = var.public_cidrs
  private_app_cidrs  = var.private_app_cidrs
  private_data_cidrs = var.private_data_cidrs
}

module "nat_gateway" {
  source                  = "../modules/nat_gateway"
  internet_gateway        = module.vpc.internet_gateway
  vpc_id                  = module.vpc.vpc_id
  public_subnet_ids       = module.vpc.public_subnet_ids
  private_app_subnet_ids  = module.vpc.private_app_subnet_ids
  private_data_subnet_ids = module.vpc.private_data_subnet_ids
}

module "load_balancer_security_group" {
  source              = "../modules/security_group"
  security_group_name = "load-balancer"
  vpc_id              = module.vpc.vpc_id
  rules = [{ type = "ingress", port = 80, cidr_blocks = ["0.0.0.0/0"], security_groups = null },
  { type = "egress", port = 9000, cidr_blocks = null, security_groups = module.app_security_group.security_group_id }]
}

module "app_security_group" {
  source              = "../modules/security_group"
  security_group_name = "application"
  vpc_id              = module.vpc.vpc_id
  rules = [{ type = "ingress", port = 9000, cidr_blocks = null, security_groups = module.load_balancer_security_group.security_group_id },
    { type = "ingress", port = 9001, cidr_blocks = null, security_groups = module.app_security_group.security_group_id },
    { type = "ingress", port = 9002, cidr_blocks = null, security_groups = module.app_security_group.security_group_id },
    { type = "ingress", port = 9003, cidr_blocks = null, security_groups = module.app_security_group.security_group_id },
    { type = "egress", port = 9001, cidr_blocks = null, security_groups = module.app_security_group.security_group_id },
    { type = "egress", port = 9002, cidr_blocks = null, security_groups = module.app_security_group.security_group_id },
    { type = "egress", port = 9003, cidr_blocks = null, security_groups = module.app_security_group.security_group_id },
    { type = "egress", port = 5432, cidr_blocks = null, security_groups = module.data_security_group.security_group_id },
  { type = "egress", port = 443, cidr_blocks = ["0.0.0.0/0"], security_groups = null }]
}

module "data_security_group" {
  source              = "../modules/security_group"
  security_group_name = "data"
  vpc_id              = module.vpc.vpc_id
  rules               = [{ type = "ingress", port = 5432, cidr_blocks = null, security_groups = module.app_security_group.security_group_id }]
}

module "load_balancer" {
  source             = "../modules/load_balancer"
  load_balancer_name = var.load_balancer_name
  public_subnet_ids  = module.vpc.public_subnet_ids
  vpc_id             = module.vpc.vpc_id
  security_groups_id = [module.load_balancer_security_group.security_group_id]
  target_ids         = module.app_EC2.instance_ids
  target_port        = var.target_port
}

module "app_EC2" {
  source            = "../modules/EC2"
  instance_type     = var.instance_type
  security_group_id = [module.app_security_group.security_group_id]
  subnet_ids        = module.vpc.private_app_subnet_ids
  instance_count    = 2
  file_path         = "../modules/EC2/sonarqube_compute_engine.sh"
  #db_write_endpoint = module.aurora.rds_writer_endpoint
}

module "aurora" {
  source                  = "../modules/aurora"
  project_name            = var.project_name
  postgres_username       = var.postgres_username
  postgres_password       = var.postgres_password
  cluster_instances_count = length(module.vpc.private_data_subnet_ids)
  private_subnets         = module.vpc.private_data_subnet_ids
  security_groups         = [module.data_security_group.security_group_id]
}

module "search_EC2" {
  source            = "../modules/EC2"
  instance_type     = var.instance_type
  security_group_id = [module.app_security_group.security_group_id]
  subnet_ids        = module.vpc.private_app_subnet_ids
  instance_count    = 3
  file_path         = "../modules/EC2/sonarqube_search_engine.sh"
  #db_write_endpoint = module.aurora.rds_writer_endpoint
}
