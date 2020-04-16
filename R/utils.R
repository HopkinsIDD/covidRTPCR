make_analysis_data <- function(stan_model,
                               data_list,
                               p_adapt_delta,
                               n_max_treedepth,
                               ...){
    ## sample from Stan model
    stan_sample <- npv_est <- sampling(stan_model,
                                       data=data_list,
                                       ...)
    ## get Stan likelihood
    stan_ll <- loo::extract_log_lik(npv_est) %>% loo::loo()

    ## extract parameters
    ## sensitivity (sens) of PCR: P(PCR+ | covid+)
    ## false negative rate (fnr) of PCR: P(PCR- | covid+) = 1 - sens
    sens <- extract(npv_est, pars="sens")[[1]]

    ## negative predictive value (npv) of PCR: P(covid- | PCR-)
    ## false omission rate (FOR) of PCR: P(covid+ | PCR-) = 1 - npv
    npv <- extract(npv_est, pars="npv")[[1]]

    ## attack rate: P(covid+)
    ## P(covid-) = 1 - attack_rate
    attack_rate <- extract(npv_est, pars="attack_rate")[[1]] %>% as.vector()

    plot_dat <- as_tibble(sens) %>%
        gather("days", "sens") %>%
        mutate(days_since_exposure=gsub(pattern="V", "", days) %>% as.numeric) %>%
        bind_cols(as_tibble(npv) %>%
                      gather("days", "npv") %>%
                      mutate(ar=rep(attack_rate, ncol(sens))) %>%
                      select(-days)) %>%
        group_by(days_since_exposure) %>%
        summarise(fnr_med=median(1-sens),
                  fnr_lb=quantile(1-sens,probs=.025),
                  fnr_ub=quantile(1-sens,probs=.975),
                  for_med=median(1-npv),
                  for_lb=quantile(1-npv,probs=.025),
                  for_ub=quantile(1-npv,probs=.975),
                  rr_med=median(1-(1-npv)/ar),
                  rr_lb=quantile(1-(1-npv)/ar,probs=.025),
                  rr_ub=quantile(1-(1-npv)/ar,probs=.975),
                  abs_med=median(ar-(1-npv)),
                  abs_lb=quantile(ar-(1-npv),probs=.025),
                  abs_ub=quantile(ar-(1-npv),probs=.975))

    return(list(plot_dat=plot_dat,
                stan_ll=stan_ll))
}
