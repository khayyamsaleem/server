pipeline {
    agent any

    triggers {
        githubPush()
    }

    options {
        timeout(time: 10, unit: 'MINUTES')
    }

    environment {
        JUUL_HOST = '172.18.0.1'
        JUUL_USER = 'root'
        JUUL_DEPLOY_DIR = '/opt/server'

        CHERRYBLOSSOM_HOST = 'cherryblossom'
        CHERRYBLOSSOM_USER = 'khayyam'
        CHERRYBLOSSOM_ROOT_USER = 'root'
        CHERRYBLOSSOM_DEPLOY_DIR = '/home/khayyam/server'

        SSH_OPTS = '-o StrictHostKeyChecking=no -o ConnectTimeout=10'
    }

    stages {
        stage('Pull') {
            parallel {
                stage('Pull juul') {
                    steps {
                        sshagent(credentials: ['server-deploy-key']) {
                            sh """
                                ssh ${SSH_OPTS} ${JUUL_USER}@${JUUL_HOST} '
                                    git -C ${JUUL_DEPLOY_DIR} fetch origin &&
                                    git -C ${JUUL_DEPLOY_DIR} reset --hard origin/master
                                '
                            """
                        }
                    }
                }
                stage('Pull cherryblossom') {
                    steps {
                        sshagent(credentials: ['server-deploy-key']) {
                            sh """
                                ssh ${SSH_OPTS} ${CHERRYBLOSSOM_USER}@${CHERRYBLOSSOM_HOST} '
                                    GIT_SSH_COMMAND="ssh -i ~/.ssh/server-deploy-key" git -C ${CHERRYBLOSSOM_DEPLOY_DIR} fetch origin &&
                                    GIT_SSH_COMMAND="ssh -i ~/.ssh/server-deploy-key" git -C ${CHERRYBLOSSOM_DEPLOY_DIR} reset --hard origin/master
                                '
                            """
                        }
                    }
                }
            }
        }

        stage('Deploy') {
            parallel {
                stage('Deploy juul') {
                    steps {
                        sshagent(credentials: ['server-deploy-key']) {
                            sh """
                                ssh ${SSH_OPTS} ${JUUL_USER}@${JUUL_HOST} '
                                    cd ${JUUL_DEPLOY_DIR}/juul &&
                                    if docker compose up -d --dry-run 2>&1 | grep -q "tailscale.*Recreate"; then
                                        echo "Tailscale will be recreated — force-recreating proxy too..."
                                        docker compose up -d --remove-orphans &&
                                        docker compose up -d --force-recreate proxy
                                    else
                                        docker compose up -d --remove-orphans
                                    fi
                                '
                            """
                        }
                    }
                }
                stage('Deploy cherryblossom') {
                    steps {
                        sshagent(credentials: ['server-deploy-key']) {
                            sh """
                                ssh ${SSH_OPTS} ${CHERRYBLOSSOM_USER}@${CHERRYBLOSSOM_HOST} '
                                    cd ${CHERRYBLOSSOM_DEPLOY_DIR}/cherryblossom &&
                                    if docker compose up -d --dry-run 2>&1 | grep -q "gluetun.*Recreate"; then
                                        echo "Gluetun will be recreated — removing transmission to avoid stale namespace..."
                                        docker rm -f transmission 2>/dev/null || true
                                    fi &&
                                    docker compose up -d --remove-orphans
                                '
                            """
                        }
                    }
                }
            }
        }

        stage('Post-deploy') {
            parallel {
                stage('MOTD juul') {
                    steps {
                        sshagent(credentials: ['server-deploy-key']) {
                            sh """
                                ssh ${SSH_OPTS} ${JUUL_USER}@${JUUL_HOST} '
                                    cp ${JUUL_DEPLOY_DIR}/juul/motd.sh /etc/update-motd.d/01-juul &&
                                    chmod 755 /etc/update-motd.d/01-juul &&
                                    rm -f /etc/update-motd.d/juul-art.txt
                                '
                            """
                        }
                    }
                }
                stage('MOTD cherryblossom') {
                    steps {
                        sshagent(credentials: ['server-deploy-key']) {
                            sh """
                                ssh ${SSH_OPTS} ${CHERRYBLOSSOM_ROOT_USER}@${CHERRYBLOSSOM_HOST} '
                                    cp ${CHERRYBLOSSOM_DEPLOY_DIR}/cherryblossom/motd.sh /etc/profile.d/motd.sh &&
                                    chmod 755 /etc/profile.d/motd.sh
                                '
                            """
                        }
                    }
                }
            }
        }

        stage('Update Jenkins') {
            steps {
                sshagent(credentials: ['server-deploy-key']) {
                    sh """
                        ssh ${SSH_OPTS} ${JUUL_USER}@${JUUL_HOST} '
                            cd ${JUUL_DEPLOY_DIR}/juul &&
                            NEEDS_UPDATE=\$(docker compose up -d --dry-run jenkins 2>&1 | grep -c "Recreate\\|Creating" || true)
                            if [ "\$NEEDS_UPDATE" -gt 0 ]; then
                                echo "Jenkins config changed — scheduling recreate in 10s..."
                                nohup sh -c "sleep 10 && cd ${JUUL_DEPLOY_DIR}/juul && docker compose up -d jenkins" > /tmp/jenkins-update.log 2>&1 &
                                echo "Scheduled. Jenkins will restart momentarily."
                            else
                                echo "Jenkins config unchanged — no restart needed."
                            fi
                        '
                    """
                }
            }
        }
    }

    post {
        failure {
            echo 'Deployment failed — check stage logs for details.'
        }
        success {
            echo 'Both nodes updated successfully.'
        }
    }
}
