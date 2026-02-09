package com.pipeline;

import javax.servlet.ServletContextEvent;
import javax.servlet.ServletContextListener;

public class ScheduleContextListener implements ServletContextListener {

    @Override
    public void contextInitialized(ServletContextEvent sce) {
        ScheduleRunner.start();
    }

    @Override
    public void contextDestroyed(ServletContextEvent sce) {}
}
