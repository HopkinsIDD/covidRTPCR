//
// This Stan program defines a model for adjusting a predicted
// seroincidence by the sensitivity and specificity of the diagnostic.
// We assume that the sensitivity of the diagnostic decays with time.
//
// Learn more about model development with Stan at:
//
//    http://mc-stan.org/users/interfaces/rstan.html
//    https://github.com/stan-dev/rstan/wiki/RStan-Getting-Started
//

// We have RT-PCR data from two studies where patients eventually developed
// antibodies (IgG or IgM) to covid-19.
// 'N' is the number of rows in our input data, which has a row for each number of
// days since symptom onset. 'T_max' is the number of days that we would like to
// predict into the future. 'test_n' is the number of people who were tested
// and 'test_pos' is the number of people who tested positive. 't_symp_test' is
// the number of days since symptom onset. 'exposed_n' and 'exposed_pos' are
// numbers to estimate the attack rate of covid-19 from other papers.
data {
    int<lower=1> N;
    int<lower=1> J; // number of studies
    int<lower=1> T_max;
    int<lower=1> test_n[N];
    int<lower=0> test_pos[N];
    matrix[N,3] t_ort;
    matrix[T_max, 3] t_new_ort;
    int<lower=1> study_idx[N];
    int<lower=1> exposed_n;
    int<lower=0> exposed_pos;
    real spec;
}

// the beta terms are the coefficients for the cubic polynomial for log-time.
// 'attack_rate' is the probability of infection given exposure.
parameters{
    real beta_0;
    real beta_1;
    real<upper=0> beta_2;
    real<lower=0> beta_3;
    real<lower=0> sigma;
    vector[J] eta;
    real<lower=0, upper=1> attack_rate;
}

// 'db_dt' is the first derivative of the log-time polynomial, which is restricted
// to be positive for the first 4 days since exposure.
transformed parameters{
    // real<lower=0> db_dt[t_exp_symp-2];
    vector[N] mu;
    vector[J] beta_j;

    // for(i in 1:(t_exp_symp-2)){
    //     db_dt[i] = beta_1+2*beta_2*(log(i)-t_mean)/t_sd+3*beta_3*((log(i)-t_mean)/t_sd)^2;
    // }

    beta_j = beta_0 + sigma*eta;

    for(i in 1:N){
        mu[i] = beta_j[study_idx[i]]+beta_1*t_ort[i,1]+beta_2*t_ort[i,2]+beta_3*t_ort[i,3];
    }
}

model {
    target += binomial_lpmf(exposed_pos | exposed_n, attack_rate);
    target += binomial_logit_lpmf(test_pos | test_n, mu);
    target += normal_lpdf(eta | 0, 1);
}

// 'sens' is the sensitivity of the RT-PCR over time for the predicted values.
// 'npv' is estimated using 'sens' and 'attack_rate'. We can also find the
// log-likelihood of the model for estimating the observed values, with the caveat
// that we don't know the likelihood of the estimates occurring prior to symptom
// onset.
generated quantities{
    vector<lower=0, upper=1>[T_max] sens;
    vector<lower=0, upper=1>[T_max] npv;
    vector[N] log_lik;

    for(i in 1:T_max){
        sens[i] = inv_logit(beta_0+beta_1*t_new_ort[i,1]+beta_2*t_new_ort[i,2]+beta_3*t_new_ort[i,3]);
    }

    for(i in 1:T_max){
        npv[i] = (spec*(1-attack_rate))/((1-sens[i])*attack_rate+spec*(1-attack_rate));
    }

    for(i in 1:N){
        log_lik[i] = binomial_logit_lpmf(test_pos[i] | test_n[i], mu[i]);
    }
}
