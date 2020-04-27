make_analysis_data <- function(dat,
                               stan_model,
                               T_max,
                               poly_est,
                               poly_pred,
                               exposed_n,
                               exposed_pos,
                               spec,
                               save_stan=F,
                               ...){
    ## sample from Stan model
    stan_sample <- sampling(stan_model,
                            data=list(N=nrow(dat),
                                      J=max(dat$study_idx),
                                      T_max=T_max,
                                      test_n=dat$n_adj,
                                      test_pos=dat$test_pos_adj,
                                      study_idx=dat$study_idx,
                                      t_ort=as.matrix(poly_est),
                                      t_new_ort=poly_pred,
                                      exposed_n=exposed_n,
                                      exposed_pos=exposed_pos,
                                      spec=spec),
                            ...)
    ## get Stan likelihood
    stan_ll <- suppressWarnings(loo::extract_log_lik(stan_sample) %>% loo::loo())

    ## extract parameters
    ## sensitivity (sens) of PCR: P(PCR+ | covid+)
    ## false negative rate (fnr) of PCR: P(PCR- | covid+) = 1 - sens
    sens <- extract(stan_sample, pars="sens")[[1]]

    ## negative predictive value (npv) of PCR: P(covid- | PCR-)
    ## false omission rate (FOR) of PCR: P(covid+ | PCR-) = 1 - npv
    npv <- extract(stan_sample, pars="npv")[[1]]

    ## attack rate: P(covid+)
    ## P(covid-) = 1 - attack_rate
    attack_rate <- extract(stan_sample, pars="attack_rate")[[1]] %>% as.vector()

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

    if(save_stan){
        return(list(plot_dat=plot_dat,
                    stan_ll=stan_ll,
                    stan_sample=stan_sample))
    } else{
        return(list(plot_dat=plot_dat,
                    stan_ll=stan_ll))
    }
}
