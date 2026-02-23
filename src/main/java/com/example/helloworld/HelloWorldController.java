package com.example.helloworld;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloWorldController {

    @GetMapping("/hello")
    public String hello() {
        return "Hello, World! 🌍 — Running inside Kubernetes via Helm";
    }

    @GetMapping("/")
    public String root() {
        return "Spring Boot Hello World App is running! Try GET /hello";
    }

}
