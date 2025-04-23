# models/account_invoice.py

from odoo import models, fields, api
from datetime import datetime


class AccountInvoice(models.Model):
    _inherit = 'account.invoice'

    contract_start_date = fields.Date(string="Contract Start Date")
    contract_end_date = fields.Date(string="Contract End Date")
    contract_total_days = fields.Integer(
        string="Contract Duration (Days)", compute='_compute_contract_days', store=True, readonly=False)

    @api.depends('contract_start_date', 'contract_end_date')
    def _compute_contract_days(self):
        for record in self:
            if record.contract_start_date and record.contract_end_date:
                delta = record.contract_end_date - record.contract_start_date
                record.contract_total_days = delta.days + 1 if delta.days >= 0 else 0
            else:
                record.contract_total_days = 0


class CustomSaleOrderLine(models.Model):
    _inherit = 'account.invoice.line'

    unit_measures = fields.Char(string='Unit of Measure', required=False)

