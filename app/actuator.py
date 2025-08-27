"""
Flask Actuator-like endpoints for monitoring and management
Similar to Spring Boot Actuator
"""
import os
import sys
import platform
import time
from datetime import datetime
from flask import jsonify
import psutil

class FlaskActuator:
    def __init__(self, app=None):
        self.app = app
        self.start_time = time.time()
        if app is not None:
            self.init_app(app)
    
    def init_app(self, app):
        """Initialize the actuator with Flask app"""
        self.app = app
        self.register_endpoints()
    
    def register_endpoints(self):
        """Register all actuator endpoints"""
        self.app.add_url_rule('/actuator', 'actuator_index', self.actuator_index)
        self.app.add_url_rule('/actuator/health', 'actuator_health', self.health)
        self.app.add_url_rule('/actuator/info', 'actuator_info', self.info)
        self.app.add_url_rule('/actuator/metrics', 'actuator_metrics', self.metrics)
        self.app.add_url_rule('/actuator/env', 'actuator_env', self.env)
        self.app.add_url_rule('/actuator/configprops', 'actuator_configprops', self.configprops)
    
    def actuator_index(self):
        """List all available actuator endpoints"""
        return jsonify({
            "_links": {
                "self": {"href": "/actuator"},
                "health": {"href": "/actuator/health"},
                "info": {"href": "/actuator/info"},
                "metrics": {"href": "/actuator/metrics"},
                "env": {"href": "/actuator/env"},
                "configprops": {"href": "/actuator/configprops"}
            }
        })
    
    def health(self):
        """Health check endpoint"""
        try:
            # Check disk space
            disk_usage = psutil.disk_usage('/')
            disk_free_percent = (disk_usage.free / disk_usage.total) * 100
            disk_status = "UP" if disk_free_percent > 10 else "DOWN"
            
            # Check memory
            memory = psutil.virtual_memory()
            memory_status = "UP" if memory.percent < 90 else "DOWN"
            
            # Overall status
            overall_status = "UP" if disk_status == "UP" and memory_status == "UP" else "DOWN"
            
            return jsonify({
                "status": overall_status,
                "components": {
                    "diskSpace": {
                        "status": disk_status,
                        "details": {
                            "total": disk_usage.total,
                            "free": disk_usage.free,
                            "threshold": disk_usage.total * 0.1,
                            "exists": True
                        }
                    },
                    "memory": {
                        "status": memory_status,
                        "details": {
                            "total": memory.total,
                            "available": memory.available,
                            "percent": memory.percent
                        }
                    },
                    "ping": {
                        "status": "UP"
                    }
                }
            })
        except Exception as e:
            return jsonify({
                "status": "DOWN",
                "details": {"error": str(e)}
            }), 503
    
    def info(self):
        """Application information"""
        uptime_seconds = int(time.time() - self.start_time)
        
        return jsonify({
            "app": {
                "name": os.getenv('APP_NAME', 'flask-web'),
                "version": os.getenv('APP_VERSION', '1.0.0'),
                "description": "Flask Web Application with Actuator",
                "uptime": f"{uptime_seconds}s"
            },
            "build": {
                "version": os.getenv('APP_VERSION', '1.0.0'),
                "artifact": os.getenv('APP_NAME', 'flask-web'),
                "name": os.getenv('APP_NAME', 'flask-web'),
                "time": os.getenv('BUILD_TIME', datetime.now().isoformat()),
                "group": "me-test"
            },
            "git": {
                "branch": os.getenv('GIT_BRANCH', 'unknown'),
                "commit": {
                    "id": os.getenv('GIT_COMMIT_HASH', 'unknown'),
                    "time": os.getenv('GIT_COMMIT_TIME', 'unknown')
                }
            },
            "environment": os.getenv('ENVIRONMENT', 'development'),
            "python": {
                "version": sys.version,
                "implementation": platform.python_implementation(),
                "version_info": {
                    "major": sys.version_info.major,
                    "minor": sys.version_info.minor,
                    "micro": sys.version_info.micro
                }
            },
            "os": {
                "name": platform.system(),
                "version": platform.release(),
                "arch": platform.machine(),
                "processor": platform.processor()
            }
        })
    
    def metrics(self):
        """System metrics"""
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            return jsonify({
                "names": [
                    "system.cpu.usage",
                    "system.memory.usage",
                    "system.memory.total",
                    "system.disk.usage",
                    "system.disk.total",
                    "process.uptime"
                ],
                "measurements": {
                    "system.cpu.usage": {
                        "statistic": "VALUE",
                        "value": cpu_percent
                    },
                    "system.memory.usage": {
                        "statistic": "VALUE", 
                        "value": memory.percent
                    },
                    "system.memory.total": {
                        "statistic": "VALUE",
                        "value": memory.total
                    },
                    "system.disk.usage": {
                        "statistic": "VALUE",
                        "value": (disk.used / disk.total) * 100
                    },
                    "system.disk.total": {
                        "statistic": "VALUE",
                        "value": disk.total
                    },
                    "process.uptime": {
                        "statistic": "VALUE",
                        "value": time.time() - self.start_time
                    }
                }
            })
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    
    def env(self):
        """Environment variables (filtered for security)"""
        safe_env_vars = {
            k: v for k, v in os.environ.items() 
            if not any(secret in k.lower() for secret in ['password', 'secret', 'key', 'token', 'credential', 'auth'])
        }
        
        return jsonify({
            "activeProfiles": [os.getenv('ENVIRONMENT', 'development')],
            "propertySources": [
                {
                    "name": "systemEnvironment",
                    "properties": {k: {"value": v} for k, v in safe_env_vars.items()}
                }
            ]
        })
    
    def configprops(self):
        """Configuration properties"""
        return jsonify({
            "contexts": {
                "application": {
                    "beans": {
                        "flask-config": {
                            "prefix": "flask",
                            "properties": {
                                "debug": os.getenv('FLASK_DEBUG', 'False'),
                                "testing": os.getenv('FLASK_TESTING', 'False'),
                                "port": os.getenv('PORT', '8080'),
                                "host": os.getenv('HOST', '0.0.0.0')
                            }
                        }
                    }
                }
            }
        })
