pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  stages {
    stage('Validate Compose') {
      steps {
        sh 'docker compose config -q'
      }
    }

    stage('Pull Base Images') {
      steps {
        sh 'docker compose pull postgres valkey adminer sonarqube || true'
      }
    }

    stage('Deploy Preprod (Main Only)') {
      when {
        branch 'main'
      }
      steps {
        sh 'docker compose up -d --build'
      }
    }
  }
}
