@Library('Shared') _
pipeline {
    agent any
    
    environment{
        // SonarQube Configuration
        SONAR_TOOL_NAME = "${env.SONAR_TOOL_NAME ?: 'Sonar'}"
        SONAR_PROJECT_KEY = "${env.SONAR_PROJECT_KEY ?: 'wanderlust'}"
        SONAR_PROJECT_NAME = "${env.SONAR_PROJECT_NAME ?: 'wanderlust'}"
        SONAR_HOME = tool 'Sonar'
        
        // Git Configuration
        GIT_REPO_URL = "${env.GIT_REPO_URL ?: 'https://github.com/Gaurav9197/Wanderlust-Mega-Project.git'}"
        GIT_BRANCH = "${env.GIT_BRANCH ?: 'main'}"
        
        // Docker Configuration
        DOCKERHUB_USERNAME = "${env.DOCKERHUB_USERNAME ?: 'gaurav9197'}"
        BACKEND_IMAGE_NAME = "${env.BACKEND_IMAGE_NAME ?: 'wanderlust-backend-beta'}"
        FRONTEND_IMAGE_NAME = "${env.FRONTEND_IMAGE_NAME ?: 'wanderlust-frontend-beta'}"
        
        // Directory Configuration
        BACKEND_DIR = "${env.BACKEND_DIR ?: 'backend'}"
        FRONTEND_DIR = "${env.FRONTEND_DIR ?: 'frontend'}"
        AUTOMATIONS_DIR = "${env.AUTOMATIONS_DIR ?: 'Automations'}"
        
        // Script Configuration
        BACKEND_ENV_SCRIPT = "${env.BACKEND_ENV_SCRIPT ?: 'updatebackendnew.sh'}"
        FRONTEND_ENV_SCRIPT = "${env.FRONTEND_ENV_SCRIPT ?: 'updatefrontendnew.sh'}"
        
        // Downstream Job Configuration
        DOWNSTREAM_JOB_NAME = "${env.DOWNSTREAM_JOB_NAME ?: 'Test-CD'}"
    }
    
    stages {
        stage("Workspace cleanup"){
            steps{
                script{
                    cleanWs()
                }
            }
        }
        
        stage('Git: Code Checkout') {
            steps {
                script{
                    code_checkout("${env.GIT_REPO_URL}","${env.GIT_BRANCH}")
                }
            }
        }
        
        stage("Generate Docker Tags") {
            steps {
                script {
                    // Get git commit SHA (first 7 characters)
                    def gitCommit = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()
                    
                    // Get build number
                    def buildNumber = env.BUILD_NUMBER
                    
                    // Generate timestamp for unique tags
                    def timestamp = sh(
                        script: 'date +%Y%m%d-%H%M%S',
                        returnStdout: true
                    ).trim()
                    
                    // Auto-generate tags
                    // Format: build-{BUILD_NUMBER}-{GIT_COMMIT}-{TIMESTAMP}
                    env.BACKEND_DOCKER_TAG = "build-${buildNumber}-${gitCommit}-${timestamp}"
                    env.FRONTEND_DOCKER_TAG = "build-${buildNumber}-${gitCommit}-${timestamp}"
                    
                    echo "Backend Docker Tag: ${env.BACKEND_DOCKER_TAG}"
                    echo "Frontend Docker Tag: ${env.FRONTEND_DOCKER_TAG}"
                }
            }
        }
        
        stage("Trivy: Filesystem scan"){
            steps{
                script{
                    trivy_scan()
                }
            }
        }

        stage("OWASP: Dependency check"){
            steps{
                script{
                    owasp_dependency()
                }
            }
        }
        
        stage("SonarQube: Code Analysis"){
            steps{
                script{
                    sonarqube_analysis("${env.SONAR_TOOL_NAME}","${env.SONAR_PROJECT_KEY}","${env.SONAR_PROJECT_NAME}")
                }
            }
        }
        
        stage("SonarQube: Code Quality Gates"){
            steps{
                script{
                    sonarqube_code_quality()
                }
            }
        }
        
        stage('Exporting environment variables') {
            parallel{
                stage("Backend env setup"){
                    steps {
                        script{
                            dir("${env.AUTOMATIONS_DIR}"){
                                sh "bash ${env.BACKEND_ENV_SCRIPT}"
                            }
                        }
                    }
                }
                
                stage("Frontend env setup"){
                    steps {
                        script{
                            dir("${env.AUTOMATIONS_DIR}"){
                                sh "bash ${env.FRONTEND_ENV_SCRIPT}"
                            }
                        }
                    }
                }
            }
        }
        
        stage("Docker: Build Images"){
            steps{
                script{
                        dir("${env.BACKEND_DIR}"){
                            docker_build("${env.BACKEND_IMAGE_NAME}","${env.BACKEND_DOCKER_TAG}","${env.DOCKERHUB_USERNAME}")
                        }
                    
                        dir("${env.FRONTEND_DIR}"){
                            docker_build("${env.FRONTEND_IMAGE_NAME}","${env.FRONTEND_DOCKER_TAG}","${env.DOCKERHUB_USERNAME}")
                        }
                }
            }
        }
        
        stage("Docker: Push to DockerHub"){
            steps{
                script{
                    docker_push("${env.BACKEND_IMAGE_NAME}","${env.BACKEND_DOCKER_TAG}","${env.DOCKERHUB_USERNAME}") 
                    docker_push("${env.FRONTEND_IMAGE_NAME}","${env.FRONTEND_DOCKER_TAG}","${env.DOCKERHUB_USERNAME}")
                }
            }
        }
    }
    post{
        always{
            // Archive test reports and scan results
            archiveArtifacts artifacts: '**/*.xml', followSymlinks: false, allowEmptyArchive: true
            archiveArtifacts artifacts: '**/coverage/**/*', followSymlinks: false, allowEmptyArchive: true
        }
        success{
            script {
                echo "CI Pipeline completed successfully!"
                echo "Backend Image: ${env.BACKEND_IMAGE_NAME}:${env.BACKEND_DOCKER_TAG}"
                echo "Frontend Image: ${env.FRONTEND_IMAGE_NAME}:${env.FRONTEND_DOCKER_TAG}"
                echo "Triggering CD pipeline: ${env.DOWNSTREAM_JOB_NAME}"
                
                // Trigger downstream CD job
                build job: "${env.DOWNSTREAM_JOB_NAME}", parameters: [
                    string(name: 'FRONTEND_DOCKER_TAG', value: "${env.FRONTEND_DOCKER_TAG}"),
                    string(name: 'BACKEND_DOCKER_TAG', value: "${env.BACKEND_DOCKER_TAG}")
                ], wait: false
            }
        }
        failure{
            script {
                echo "CI Pipeline failed. Check logs for details."
            }
        }
        unstable{
            script {
                echo "CI Pipeline completed with warnings. Review quality gates."
            }
        }
    }
}
